# Simply Measured kong plugins
Kong is an application that sits in front of the simply measured micro service ecosystem. It proxies and authenticates requests among other things. The current kong configuration is kept at https://github.com/simplymeasured/kong-config.

Kong allows for custom plugins to be added and at Simply Measured we have written a few and modified existing plugins for our needs. This repo contains the plugins that have been modified from the original. For more information on native kong plugins (several of which are used) the docs can be found https://getkong.org/plugins/.


## Customized Plugins

----------------------

#### Activity Id plugin
If the `x-sm-activity-id` header is missing in a request, this plugin sets that header to a guid. The activity id header is used to trace calls through the backend services so it's important that all requests have one present. If the header exists it will respect it.

#### JWT auth plugin
In addition to the standard JWT plugin, we expose the user-id as a header to downstream plugins.

#### sm-syslog plugin
This sends details about every proxied request to syslog including: request timings, response codes, headers and more. Logs are surfaced at http://kibana.prod.pdx.intsm.net/

#### sm-datadog plugin
Metrics about each api such as proxy timings and response codes are recorded in graphite and surfaced at https://grafana.prod.pdx.intsm.net/

### Rate limiting
There are 2 different types of rate limiting implemented in our stack, the type of which is determined by the signature of their jwt.
* JWT's that have been generated through the data portal have a rate limit block inside the JWT. The rate limits are attached to their plan and when the JWT is generated the limits are inserted from a call to UAM. The rate limit key is the account-id.
* JWT's coming from viper are rate limited by the user-id in the JWT and are rate limited at an unfeasibly high level. This is meant to stop ddos'ing attacks if a user grabbed their auth token from their browsing session.
