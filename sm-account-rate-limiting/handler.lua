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

local function increment(client_id, account_id, current_timestamp, value)
    -- Increment metrics for all periods if the request goes through
    local _, stmt_err = singletons.dao.account_ratelimiting_metrics:increment(client_id, account_id, current_timestamp, value)
    if stmt_err then
        return false, stmt_err
    end
    return true
end

local function increment_async(premature, client_id, account_id, current_timestamp, value)
    if premature then return end

    local _, stmt_err = singletons.dao.account_ratelimiting_metrics:increment(client_id, account_id, current_timestamp, value)
    if stmt_err then
        ngx.log(ngx.ERR, "failed to increment: ", tostring(stmt_err))
    end
end

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

local function get_usage(client_id, account_id, current_timestamp, limits)
    local usage = {}
    local stop

    for name, limit in pairs(limits) do
        local current_metric, err = singletons.dao.account_ratelimiting_metrics:find(client_id, account_id, current_timestamp, name)
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

    if is_empty(rate_limits) then
        return responses.send_HTTP_BAD_REQUEST("Could not find any rate limits in JWT claims.  This plugin works only with monthly and minute account limits.")
    end

    local is_async = conf.async
    local is_continue_on_error = conf.continue_on_error

    -- Load current metric for configured period
    conf.async = nil
    conf.continue_on_error = nil
    local usage, stop, err = get_usage(client_id, account_id, current_timestamp, rate_limits)
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
            ngx.header["X-Rate-Limit-"..k] = v.limit
            ngx.header["X-Rate-Limit-Remaining-"..k] = math.max(0, (stop == nil or stop == k) and v.remaining - 1 or v.remaining) -- -increment_value for this current request
        end

        -- If limit is exceeded, terminate the request
        if stop then
            return responses.send(429, "API rate limit exceeded")
        end
    end

    -- Increment metrics for all periods if the request goes through
    if is_async then
        local ok, err = ngx.timer.at(0, increment_async, client_id, account_id, current_timestamp, 1)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
        end
    else
        local _, err = increment(client_id, account_id, current_timestamp, 1)
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
