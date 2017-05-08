local crud = require "kong.api.crud_helpers"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local app_helpers = require "lapis.application"

return {
  ["/maintenance/"] = {
    GET = function(self, dao_factory)
      enabled = cache.get('maintenance_mode')
      mode = {enabled=false}
      
      if enabled ~= nil then
        mode['enabled'] = enabled
      end

      return responses.send_HTTP_OK(mode, type(mode) ~= "table")
    end,

    PUT = function(self, dao_factory)
      enabled = self.params.enabled
      if type(enabled) ~= "boolean" then
        return responses.send(422, "Value for 'enabled' must be either true or false") 
      end
          
      ok, err = cache.set('maintenance_mode', enabled)

      if err ~= nil then
        return app_helpers.yield_error(err)
      end
      
      mode = {enabled=enabled}
      return responses.send_HTTP_OK(mode, type(mode) ~= "table")
    end,
  },
  ["/healthcheck"] = {
    GET = function(self, dao_factory)
      maint_enabled = cache.get('maintenance_mode')
      healthcheck = {maintenance_mode=false}

      if maint_enabled ~= nil then
        healthcheck['maintenance_mode'] = maint_enabled
      end

      if healthcheck['maintenance_mode'] then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(healthcheck, type(healthcheck) ~= "table")
      end

      return responses.send_HTTP_OK(healthcheck, type(healthcheck) ~= "table")
    end,
  }
}
