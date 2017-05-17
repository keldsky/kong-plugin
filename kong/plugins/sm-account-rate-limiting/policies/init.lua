local singletons = require "kong.singletons"
local timestamp = require "kong.tools.timestamp"
local cache = require "kong.tools.database_cache"
local policy_cluster = require "kong.plugins.sm-account-rate-limiting.policies.cluster"
local ngx_log = ngx.log

local pairs = pairs
local fmt = string.format

local get_local_key = function(identifier, period_date, name)
  return fmt("ratelimit:%s:%s:%s", identifier, period_date, name)
end

local EXPIRATIONS = {
  second = 1,
  minute = 60,
  hour = 3600,
  day = 86400,
  month = 2592000,
  year = 31536000,
}

return {
  ["cluster"] = {
    increment = function(conf, identifier, current_timestamp, value)
      local db = singletons.dao.db
      local ok, err = policy_cluster[db.name].increment(db, identifier, current_timestamp, value)
      if not ok then
        ngx_log(ngx.ERR, "[sm-account-rate-limiting] cluster policy: could not increment ", db.name, " counter: ", err)
      end

      return ok, err
    end,
    usage = function(conf, identifier, current_timestamp, name)
      local db = singletons.dao.db
      local row, err = policy_cluster[db.name].find(db, identifier, current_timestamp, name)

      if err then
        ngx_log(ngx.ERR, "row not found"..err)
        return nil, err
      end

      return row and row.value or 0
    end
  }
}
