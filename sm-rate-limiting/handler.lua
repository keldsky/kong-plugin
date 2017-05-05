-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local constants = require "kong.constants"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local singletons = require "kong.singletons"

local req_get_headers = ngx.req.get_headers
local RateLimitingHandler = BasePlugin:extend()

RateLimitingHandler.PRIORITY = 900

local function increment(api_id, identifier, current_timestamp, value)
  -- Increment metrics for all periods if the request goes through
  local _, stmt_err = singletons.dao.ratelimiting_metrics:increment(api_id, identifier, current_timestamp, value)
  if stmt_err then
    return false, stmt_err
  end
  return true
end

local function increment_async(premature, api_id, identifier, current_timestamp, value)
  if premature then return end
  
  local _, stmt_err = singletons.dao.ratelimiting_metrics:increment(api_id, identifier, current_timestamp, value)
  if stmt_err then
    ngx.log(ngx.ERR, "failed to increment: ", tostring(stmt_err))
  end
end

local function get_user_id()
    local headers = req_get_headers()
    local authHeader = headers["Authorization"]

    if not authHeader then
        return responses.send_HTTP_BAD_REQUEST("JWT authorization must be enabled to use this plugin.")
    end

    local jwt, err = jwt_decoder:new(authHeader:gsub("[B,b]earer ", ""))
    if err then
        return responses.send_HTTP_BAD_REQUEST("Failed to decode JWT:  " .. tostring(err))
    end

    return jwt.claims["user_id"]:gsub("auth0|", "")
end

local function get_usage(api_id, identifier, current_timestamp, limits)
  local usage = {}
  local stop

  for name, limit in pairs(limits) do
    local current_metric, err = singletons.dao.ratelimiting_metrics:find(api_id, identifier, current_timestamp, name)
    if err then
      return nil, nil, err
    end

    -- What is the current usage for the configured limit name?
    local current_usage = current_metric and current_metric.value or 0
    local remaining = limit - current_usage

    -- Recording usage
    usage[name] = {
      limit = limit,
      remaining = remaining
    }

    if remaining <= 0 then
      stop = name
    end
  end

  return usage, stop
end

function RateLimitingHandler:new()
  RateLimitingHandler.super.new(self, "sm-rate-limiting")
end

function RateLimitingHandler:access(conf)
  RateLimitingHandler.super.access(self)
  local current_timestamp = timestamp.get_utc()

  -- Consumer is identified by ip address or authenticated_credential id
  local identifier = get_user_id()
  local api_id = ngx.ctx.api.id
  local is_async = conf.async
  local is_continue_on_error = conf.continue_on_error

  -- Load current metric for configured period
  conf.async = nil
  conf.continue_on_error = nil
  local usage, stop, err = get_usage(api_id, identifier, current_timestamp, conf)
  if err then
    if is_continue_on_error then
      ngx.log(ngx.ERR, "failed to get usage: ", tostring(err))
    else
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end

  if usage then
    -- Adding headers
    for k, v in pairs(usage) do
      ngx.header[constants.HEADERS.RATELIMIT_LIMIT.."-"..k] = v.limit
      ngx.header[constants.HEADERS.RATELIMIT_REMAINING.."-"..k] = math.max(0, (stop == nil or stop == k) and v.remaining - 1 or v.remaining) -- -increment_value for this current request
    end

    -- If limit is exceeded, terminate the request
    if stop then
      return responses.send(429, "API rate limit exceeded")
    end
  end
  
  -- Increment metrics for all periods if the request goes through
  if is_async then
    local ok, err = ngx.timer.at(0, increment_async, api_id, identifier, current_timestamp, 1)
    if not ok then
      ngx.log(ngx.ERR, "failed to create timer: ", err)
    end
  else
    local _, err = increment(api_id, identifier, current_timestamp, 1)
    if err then
      if is_continue_on_error then
        ngx.log(ngx.ERR, "failed to increment: ", tostring(err))
      else
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
    end
  end
end

return RateLimitingHandler
