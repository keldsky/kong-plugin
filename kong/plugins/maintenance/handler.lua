local BasePlugin = require "kong.plugins.base_plugin"

local MaintenanceHandler = BasePlugin:extend()

MaintenanceHandler.PRIORITY = 101

function MaintenanceHandler:new()
  MaintenanceHandler.super.new(self, "maintenance")
end

return MaintenanceHandler
