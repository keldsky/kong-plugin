local timestamp = require "kong.tools.timestamp"

local concat = table.concat
local pairs = pairs
local fmt = string.format
local log = ngx.log
local ERR = ngx.ERR

return {
  ["postgres"] = {
    increment = function(db, client_id, account_id, current_timestamp, value)
      local buf = {}
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        buf[#buf+1] = fmt([[
          SELECT increment_sm_account_rate_limits('%s', '%s', '%s', to_timestamp('%s') at time zone 'UTC', %d)
        ]], client_id, account_id, period, period_date/1000, value)
      end

      local query = concat(buf, ";")
      ngx.log(ngx.DEBUG, "querying postgres for "..query)

      local res, err = db:query(query)
      if not res then return nil, err end

      return true
    end,
    find = function(db, client_id, account_id, current_timestamp, period)
      local periods = timestamp.get_timestamps(current_timestamp)

      local query = fmt([[
        SELECT *, extract(epoch from period_date)*1000 AS period_date
        FROM sm_account_ratelimiting_metrics
        WHERE client_id = '%s' AND
              account_id = '%s' AND
              period_date = to_timestamp('%s') at time zone 'UTC' AND
              period = '%s'
      ]], client_id, account_id, periods[period]/1000, period)

      ngx.log(ngx.DEBUG, "querying postgres for "..query)

      local response, err = db:query(query)
      if not response or err then return nil, err end

      return response[1]
    end,
  }
}
