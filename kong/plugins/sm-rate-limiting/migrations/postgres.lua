return {
  {
    name = "2015-08-03-132400_init_sm_user_ratelimiting_metrics",
    up = [[
      CREATE TABLE IF NOT EXISTS sm_user_ratelimiting_metrics(
        identifier text,
        period text,
        period_date timestamp without time zone,
        value integer,
        PRIMARY KEY (identifier, period_date, period)
      );

      CREATE OR REPLACE FUNCTION increment_sm_user_rate_limits(i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE sm_user_ratelimiting_metrics SET value = value + v WHERE identifier = i AND period = p AND period_date = p_date;
          IF found then
            RETURN;
          END IF;

          BEGIN
            INSERT INTO sm_user_ratelimiting_metrics(period, period_date, identifier, value) VALUES(p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN

          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = [[
      DROP TABLE sm_user_ratelimiting_metrics;
    ]]
  },
  {
    name = "2016-07-25-471385_sm_user_ratelimiting_policies",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "sm-user-rate-limiting"}
      if err then return err end

      for i = 1, #rows do
        local sm_user_rate_limiting = rows[i]

        -- Delete the old one to avoid conflicts when inserting the new one
        local _, err = dao.plugins:delete(sm_user_rate_limiting)
        if err then return err end

        local _, err = dao.plugins:insert {
          name = "sm-user-rate-limiting",
          api_id = sm_user_rate_limiting.api_id,
          consumer_id = sm_user_rate_limiting.consumer_id,
          enabled = sm_user_rate_limiting.enabled,
          config = {
            second = sm_user_rate_limiting.config.second,
            minute = sm_user_rate_limiting.config.minute,
            hour = sm_user_rate_limiting.config.hour,
            day = sm_user_rate_limiting.config.day,
            month = sm_user_rate_limiting.config.month,
            year = sm_user_rate_limiting.config.year,
            limit_by = "consumer",
            policy = "cluster",
            fault_tolerant = sm_user_rate_limiting.config.continue_on_error
          }
        }
        if err then return err end
      end
    end
  }
}
