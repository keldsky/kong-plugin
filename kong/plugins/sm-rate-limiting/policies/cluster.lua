local timestamp = require "kong.tools.timestamp"

local concat = table.concat
local pairs = pairs
local fmt = string.format
local log = ngx.log
local ERR = ngx.ERR

return {
  ["postgres"] = {
    increment = function(db, api_id, identifier, current_timestamp, value)
      local buf = {}
      local periods = timestamp.get_timestamps(current_timestamp)

      for period, period_date in pairs(periods) do
        buf[#buf+1] = fmt([[
          SELECT increment_rate_limits('%s', '%s', '%s', to_timestamp('%s')
          at time zone 'UTC', %d)
        ]], api_id, identifier, period, period_date/1000, value)
      end

      local res, err = db:query(concat(buf, ";"))
      if not res then return nil, err end

      return true
    end,
    find = function(db, api_id, identifier, current_timestamp, period)
      local periods = timestamp.get_timestamps(current_timestamp)

      local q = fmt([[
        SELECT *, extract(epoch from period_date)*1000 AS period_date
        FROM sm_ratelimiting_metrics
        WHERE api_id = '%s' AND
              identifier = '%s' AND
              period_date = to_timestamp('%s') at time zone 'UTC' AND
              period = '%s'
      ]], api_id, identifier, periods[period]/1000, period)

      local res, err = db:query(q)
      if not res or err then return nil, err end

      return res[1]
    end,
  }
}
