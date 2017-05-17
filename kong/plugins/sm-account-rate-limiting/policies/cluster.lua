local timestamp = require "kong.tools.timestamp"

local concat = table.concat
local pairs = pairs
local fmt = string.format
local log = ngx.log
local ERR = ngx.ERR

return {
  ["postgres"] = {
    increment = function(db, identifier, current_timestamp, value)
      ngx.log(ngx.ERR, "identifier: "..tostring(identifier).." current_timestamp: "..current_timestamp.." value "..value)
      local buf = {}
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        buf[#buf+1] = fmt([[
          SELECT increment_sm_account_rate_limits('%s', '%s', to_timestamp('%s') at time zone 'UTC', %d)
        ]], identifier, period, period_date/1000, value)
      end

      local query = concat(buf, ";")
      ngx.log(ngx.ERR, "query: "..query);

      local res, err = db:query(query)
      if not res then return nil, err end

      return true
    end,
    find = function(db, identifier, current_timestamp, period)
      local periods = timestamp.get_timestamps(current_timestamp)

      local query = fmt([[
        SELECT *, extract(epoch from period_date)*1000 AS period_date
        FROM sm_account_ratelimiting_metrics
        WHERE identifier = '%s' AND
              period_date = to_timestamp('%s') at time zone 'UTC' AND
              period = '%s'
      ]], identifier, periods[period]/1000, period)

      ngx.log(ngx.ERR, "query: "..query);

      local response, err = db:query(query)
      if not response or err then return nil, err end

      ngx.log(ngx.ERR, "response: "..tostring(response[0]))

      return response[1]
    end,
  }
}
