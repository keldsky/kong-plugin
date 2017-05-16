-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local policies = require "kong.plugins.sm-account-rate-limiting.policies.init"
local timestamp = require "kong.tools.timestamp"
local responses = require "kong.tools.responses"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

local req_get_headers = ngx.req.get_headers
local ngx_log = ngx.log
local pairs = pairs
local tostring = tostring
local ngx_timer_at = ngx.timer.at

local RateLimitingHandler = BasePlugin:extend()

RateLimitingHandler.PRIORITY = 900

local function get_jwt()
    local headers = req_get_headers()
    local authHeader = headers["Authorization"]

    if not authHeader then
        return responses.send_HTTP_BAD_REQUEST("JWT authorization must be enabled to use this plugin.")
    end

    local jwt, err = jwt_decoder:new(authHeader:gsub("[B,b]earer ", ""))
    if err then
        return responses.send_HTTP_BAD_REQUEST("Failed to decode JWT:  " .. tostring(err))
    end

    return jwt
end

local function is_empty(str)
    return str == nil or str == ''
end

local function parse_claim(jwt, key)
    local value = jwt.claims[key]

    if is_empty(value) then
        return responses.send_HTTP_BAD_REQUEST("Could not find "..key.." in JWT")
    end

    return value
end

local function get_usage(conf, api_id, identifier, current_timestamp, limits)
    local usage = {}
    local stop

    for name, limit in pairs(limits) do
        local current_usage, err = policies[conf.policy].usage(conf, api_id, identifier, current_timestamp, name)
        if err then
            return nil, nil, err
        end

        -- What is the current usage for the configured limit name?
        local remaining = limit - current_usage

        -- Recording usage
        usage[name] = {
            limit = limit,
            remaining = remaining
        }

        ngx.log(ngx.NOTICE, "Limit:  "..limit.."  Remaining:  "..remaining)

        if remaining <= 0 then
            stop = name
        end
    end

    return usage, stop
end

function RateLimitingHandler:new()
    RateLimitingHandler.super.new(self, "sm-account-rate-limiting")
end

function RateLimitingHandler:access(conf)
    RateLimitingHandler.super.access(self)
    local current_timestamp = timestamp.get_utc()

    -- NOTE:  the order in which the following fields are parsed is important, as account_id will not be present in UI JWTs
    -- If the client_id in the JWT does not match the client ID specified in the plugin config, we will continue.
    -- This allows us to limit only certain clients (e.g., developer tokens)
    local jwt = get_jwt()
    local client_id = parse_claim(jwt, "aud")

    if not (client_id == conf.client_id) then
        return
    end

    local account_id = parse_claim(jwt, "account_id")
    local rate_limits = parse_claim(jwt, "ratelimit")
    local api_id = ngx.ctx.api.id
    local policy = conf.policy
    local fault_tolerant = conf.fault_tolerant

    if is_empty(rate_limits) then
        return responses.send_HTTP_BAD_REQUEST("Could not find any rate limits in JWT claims.  This plugin works only with monthly and minute account limits.")
    end

    -- We use the client_id/account_id found in the JWT as the "identifier" in the other rate limiting plugins
    local identifier = client_id .. account_id

    -- Load current metric for configured period
    -- local usage, stop, err = get_usage(client_id, account_id, current_timestamp, rate_limits)
    local usage, stop, err = get_usage(conf, api_id, identifier, current_timestamp, {
      second = conf.second,
      minute = conf.minute,
      hour = conf.hour,
      day = conf.day,
      month = conf.month,
      year = conf.year})
    if err then
        if fault_tolerant then
            ngx.log(ngx.ERR, "failed to get usage: ", tostring(err))
        else
            return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
        end
    end

    if usage then
        -- Adding headers
        for k, v in pairs(usage) do
            ngx.header["X-Account-Rate-Limit-"..k] = v.limit
            ngx.header["X-Account-Rate-Limit-Remaining-"..k] = math.max(0, (stop == nil or stop == k) and v.remaining - 1 or v.remaining) -- -increment_value for this current request
        end

        -- If limit is exceeded, terminate the request
        if stop then
            return responses.send(429, "API rate limit exceeded")
        end
    end

    local incr = function(premature, conf, api_id, identifier, current_timestamp, value)
      if premature then return end
      policies[policy].increment(conf, api_id, identifier, current_timestamp, value)
    end

    -- Increment metrics for all periods if the request goes through
    local ok, err = ngx_timer_at(0, incr, conf, api_id, identifier, current_timestamp, 1)
    if not ok then
      ngx_log(ngx.ERR, "failed to create timer: ", err)
    end
end

return RateLimitingHandler
