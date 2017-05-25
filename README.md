# Simply Measured kong plugins
Kong is an application that sits in front of the simply measured micro service ecosystem. It proxies and authenticates requests among other things. The current kong configuration is kept at https://github.com/simplymeasured/kong-config.

Kong allows for custom plugins to be added and at Simply Measured we have written a few and modified existing plugins for our needs. This repo contains the plugins that have been modified from the original. For more information on native kong plugins (several of which are used) the docs can be found https://getkong.org/plugins/.

Plugins are built/deployed from https://ci.simplymeasured.com/job/kong-plugin-packaging/

## Running

----------------------

1. Clone the [Kong Vagrant repo](https://github.com/Mashape/kong-vagrant).
2. Clone this repo and [Kong](https://github.com/Mashape/kong) *parallel* to Kong Vagrant.
3. Start up Vagrant.
4. Set up your Kong config file by adding in the custom plugins that you will be using and the path to them:
```bash 
sudo luarocks install uuid
cp /kong/kong.conf.default /kong/kong.conf
custom_plugins=$(ls /kong-plugin/kong/plugins/ | sed 's/ /\n/g' | tr '\n' ',')
echo "custom_plugins = ${custom_plugins/%,/}" >> /kong/kong.conf
echo "lua_package_path = /kong-plugin/?.lua;;" >> /kong/kong.conf
```
5. `cd /kong; sudo make dev`
6. When you start Kong, pass this config in like so:  `sudo kong start -c /kong/kong.conf`

## Deploying

----------------------

1. Submit a PR with your changes on this repo.
1. Once your PR has been approved and merged, a [Jenkins job](https://ci.simplymeasured.com/job/kong-plugin-packaging/) will package your changes.
1. Once your changes have been packaged, you'll need to deploy them to each node.  Currently this is a bit tedious and manual, but here is a script (modify `env` to suit your needs): 
```bash
env="stg"; for n in $(curl https://consul.$env.pdx.intsm.net/v1/catalog/nodes | jq '.' | grep "kong" | grep -v "cassandra" | awk {'print $2'} | sed 's/\"//g' | sed 's/,//g'); do echo "DEPLOYING TO $n"; yes | ssh $n.$env.pdx.intsm.net "sudo apt-get update; yes | sudo apt-get install kong-plugin"; done
```
1. Once your plugins have been deployed to each Kong node, you'll need to then add your plugin(s) to [Kong's cookbook](https://github.com/simplymeasured/chef/blob/master/cookbooks/sm-kong/attributes/config.rb#L23-L30) to be enabled. (IMPORTANT your plugins must already be deployed as described in step #3 before you enable your plugins).


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
