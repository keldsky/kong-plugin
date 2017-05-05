local BasePlugin = require "kong.plugins.base_plugin"

local uuid = require("uuid")
local req_get_headers = ngx.req.get_headers

local ActivityIDHandler = BasePlugin:extend()

function ActivityIDHandler:new()
  ActivityIDHandler.super.new(self, "sm-activity-id")
end

function ActivityIDHandler:access(conf)
  ActivityIDHandler.super.access(self)

    local headers = req_get_headers()
    local activity_id = headers["X-SM-Activity-Id"]
    if not activity_id then
        ngx.req.set_header("X-SM-Activity-Id", uuid())
    end
end

return ActivityIDHandler
