local singletons = require "kong.singletons"
local BasePlugin = require "kong.plugins.base_plugin"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"
local string_format = string.format
local ngx_re_gmatch = ngx.re.gmatch


local JwtHandler = BasePlugin:extend()

JwtHandler.PRIORITY = 1001

local CONSUMER_ID          = "X-Consumer-ID"
local CONSUMER_CUSTOM_ID   = "X-Consumer-Custom-ID"
local CONSUMER_USERNAME    = "X-Consumer-Username"
local JWT_USER_ID          = "X-Jwt-User-Id"
local JWT_ACCOUNT_ID       = "X-Jwt-Account-Id"
local JWT_RATELIMIT_MONTH  = "X-Jwt-Ratelimit-Month"
local JWT_RATELIMIT_MINUTE = "X-Jwt-Ratelimit-Minute"

local function is_blank(str)
    return str == nil or str == ''
end

--- Retrieve a JWT in a request.
-- Checks for the JWT in URI parameters, then in the `Authorization` header.
-- @param request ngx request object
-- @param conf Plugin configuration
-- @return token JWT token contained in request or nil
-- @return err
local function retrieve_token(request, conf)
  local uri_parameters = request.get_uri_args()

  for _, v in ipairs(conf.uri_param_names) do
    if uri_parameters[v] then
      return uri_parameters[v]
    end
  end

  local authorization_header = request.get_headers()["authorization"]
  if authorization_header then
    local iterator, iter_err = ngx_re_gmatch(authorization_header, "\\s*[Bb]earer\\s+(.+)")
    if not iterator then
      return nil, iter_err
    end

    local m, err = iterator()
    if err then
      return nil, err
    end

    if m and #m > 0 then
      return m[1]
    end
  end
end

function JwtHandler:new()
  JwtHandler.super.new(self, "jwt")
end

function JwtHandler:access(conf)
  JwtHandler.super.access(self)
  local token, err = retrieve_token(ngx.req, conf)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if not token then
    return responses.send_HTTP_UNAUTHORIZED()
  end

  -- Decode token to find out who the consumer is
  local jwt, err = jwt_decoder:new(token)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR()
  end

  local claims = jwt.claims

  local jwt_secret_key = claims[conf.key_claim_name]
  if not jwt_secret_key then
    return responses.send_HTTP_UNAUTHORIZED("No mandatory '"..conf.key_claim_name.."' in claims")
  end

  -- Retrieve the secret
  local jwt_secret = cache.get_or_set(cache.jwtauth_credential_key(jwt_secret_key), function()
    local rows, err = singletons.dao.jwt_secrets:find_all {key = jwt_secret_key}
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR()
    elseif #rows > 0 then
      return rows[1]
    end
  end)

  if not jwt_secret then
    return responses.send_HTTP_FORBIDDEN("No credentials found for given '"..conf.key_claim_name.."'")
  end

  local algorithm = jwt_secret.algorithm or "HS256"

  -- Verify "alg"
  if jwt.header.alg ~= algorithm then
    return responses.send_HTTP_FORBIDDEN("Invalid algorithm")
  end

  local jwt_secret_value = algorithm == "HS256" and jwt_secret.secret or jwt_secret.rsa_public_key
  if conf.secret_is_base64 then
    jwt_secret_value = jwt:b64_decode(jwt_secret_value)
  end

  -- Now verify the JWT signature
  if not jwt:verify_signature(jwt_secret_value) then
    return responses.send_HTTP_FORBIDDEN("Invalid signature")
  end

  -- Verify the JWT registered claims
  local ok_claims, errors = jwt:verify_registered_claims(conf.claims_to_verify)
  if not ok_claims then
    return responses.send_HTTP_FORBIDDEN(errors)
  end

  -- Retrieve the consumer
  local consumer = cache.get_or_set(cache.consumer_key(jwt_secret_key), function()
    local consumer, err = singletons.dao.consumers:find {id = jwt_secret.consumer_id}
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return consumer
  end)

  -- However this should not happen
  if not consumer then
    return responses.send_HTTP_FORBIDDEN(string_format("Could not find consumer for '%s=%s'", conf.key_claim_name, jwt_secret_key))
  end

  ngx.req.set_header(CONSUMER_ID, consumer.id)
  ngx.req.set_header(CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx.req.set_header(CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_credential = jwt_secret

  -- Set values used by other sm plugins

  -- user_id
  if not is_blank(jwt.claims["user_id"]) then
    user_id = jwt.claims["user_id"]:gsub("auth0|", "")
    ngx.req.set_header(JWT_USER_ID, user_id)
  end

  -- account_id
  if not is_blank(jwt.claims["account_id"]) then
    ngx.req.set_header(JWT_ACCOUNT_ID, jwt.claims["account_id"])
  end

  -- rate_limit
  ratelimit = jwt.claims["ratelimit"]
  if not (ratelimit == nil) then
      if not (ratelimit["month"] == nil) then
        ngx.req.set_header(JWT_RATELIMIT_MONTH, ratelimit["month"])
      end

      if not (ratelimit["minute"] == nil) then
        ngx.req.set_header(JWT_RATELIMIT_MINUTE, ratelimit["minute"])
      end
  end
end

return JwtHandler
