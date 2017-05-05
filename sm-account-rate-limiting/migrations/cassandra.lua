return {
    {
    name = "2016-05-03-132400_init_account_ratelimiting",
    up = [[
        CREATE TABLE IF NOT EXISTS account_ratelimiting_metrics(
        client_id varchar,
        account_id varchar,
        period text,
        period_date timestamp,
        value counter,
        PRIMARY KEY ((client_id, account_id, period_date, period))
        );
        ]],
    down = [[
        DROP TABLE account_ratelimiting_metrics;
        ]]
    }
}
