return {
  {
    name = "2015-08-03-132400_init_sm_account_ratelimiting",
    up = [[
      CREATE TABLE IF NOT EXISTS sm_account_ratelimiting_metrics(
        identifier text,
        period text,
        period_date timestamp without time zone,
        value integer,
        PRIMARY KEY (identifier, period_date, period)
      );

      CREATE OR REPLACE FUNCTION increment_sm_account_rate_limits(i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE sm_account_ratelimiting_metrics SET value = value + v WHERE identifier = i AND period = p AND period_date = p_date;
          IF found then
            RETURN;
          END IF;

          BEGIN
            INSERT INTO sm_account_ratelimiting_metrics(period, period_date, identifier, value) VALUES(p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN

          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = [[
      DROP TABLE sm_account_ratelimiting_metrics;
    ]]
  },
  {
    name = "2016-07-25-471385_sm_account_ratelimiting_policies",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "sm-account-rate-limiting"}
      if err then return err end

      for i = 1, #rows do
        local rate_limiting = rows[i]

        -- Delete the old one to avoid conflicts when inserting the new one
        local _, err = dao.plugins:delete(rate_limiting)
        if err then return err end

        local _, err = dao.plugins:insert {
          name = "sm-account-rate-limiting",
          consumer_id = rate_limiting.consumer_id,
          enabled = rate_limiting.enabled,
          config = {
            second = rate_limiting.config.second,
            minute = rate_limiting.config.minute,
            hour = rate_limiting.config.hour,
            day = rate_limiting.config.day,
            month = rate_limiting.config.month,
            year = rate_limiting.config.year,
            client_id = rate_limiting.config.client_id,
            policy = "cluster",
            fault_tolerant = rate_limiting.config.continue_on_error
          }
        }
        if err then return err end
      end
    end
  }
}
