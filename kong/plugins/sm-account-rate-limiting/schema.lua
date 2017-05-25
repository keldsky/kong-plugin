local Errors = require "kong.dao.errors"

return {
  fields = {
    client_id = { type = "string" },
    policy = { type = "string", enum = {"cluster"}, default = "cluster" },  -- currently, the only accepted policy is "cluster", but we can add other back in if needed
    fault_tolerant = { type = "boolean", default = true }
  },
  self_check = function(schema, plugin_t, dao, is_update)
    if not plugin_t['client_id'] then
      return false, Errors.schema "This plugin requires a client ID"
    end

    return true
  end
}
