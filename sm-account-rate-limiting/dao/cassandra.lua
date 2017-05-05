local CassandraDB = require "kong.dao.cassandra_db"
local cassandra = require "cassandra"
local timestamp = require "kong.tools.timestamp"

local ngx_log = ngx and ngx.log or print
local ngx_err = ngx and ngx.ERR
local tostring = tostring


local _M = CassandraDB:extend()

_M.table = "account_ratelimiting_metrics"
_M.schema = require("kong.plugins.sm-account-rate-limiting.schema")

function _M:increment(client_id, account_id, current_timestamp, value)
    local periods = timestamp.get_timestamps(current_timestamp)
    local options = self:_get_conn_options()
    local session, err = cassandra.spawn_session(options)
    if err then
        ngx_log(ngx_err, "[account-rate-limiting] could not spawn session to Cassandra: "..tostring(err))
        return
    end

    local ok = true
    for period, period_date in pairs(periods) do
        local res, err = session:execute([[
        UPDATE account_ratelimiting_metrics SET value = value + ? WHERE
        client_id = ? AND
        account_id = ? AND
        period_date = ? AND
        period = ?
        ]], 
        {
            cassandra.counter(value),
            client_id,
            account_id,
            cassandra.timestamp(period_date),
            period
        })
        if not res then
            ok = false
            ngx_log(ngx_err, "[account-rate-limiting] could not increment counter for period '"..period.."': ", tostring(err))
        end
    end

    session:set_keep_alive()

    return ok
end

function _M:find(client_id, account_id, current_timestamp, period)
    local periods = timestamp.get_timestamps(current_timestamp)

    local rows, err = self:query([[
    SELECT * FROM account_ratelimiting_metrics WHERE
    client_id = ? AND
    account_id = ? AND
    period_date = ? AND
    period = ?
    ]], {
        client_id,
        account_id,
        cassandra.timestamp(periods[period]),
        period
    })
    if err then
        return nil, err
        elseif #rows > 0 then
            return rows[1]
        end
    end

    function _M:count()
        return _M.super.count(self, _M.table, nil, _M.schema)
    end

    return {account_ratelimiting_metrics = _M}
