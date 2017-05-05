return {
  fields = {
    client_id = {type = "string", required = true},
    async = { type = "boolean", default = false },
    continue_on_error = { type = "boolean", default = false }
  }
}
