return {
  {
    name = "2017-08-15-jwt-base-64",
    up = [[
      ALTER TABLE jwt_secrets ADD COLUMN secret_is_base64 boolean NOT NULL DEFAULT TRUE;
    ]],
    down = [[
      ALTER TABLE jwt_secrets DROP COLUMN secret_is_base64;
    ]]
  }
}
