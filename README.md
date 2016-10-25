# Logstash OpenWhisk input plugin

[![Travis Build Status](https://travis-ci.org/jthomas/logstash-input-openwhisk.svg)](https://travis-ci.org/jthomas/logstash-input-openwhisk)

This [Logstash](https://github.com/elastic/logstash) input plugin allows you to drain Activation logs from OpenWhisk. The HTTP polling service uses the [OpenWhisk API](https://github.com/openwhisk/openwhisk/blob/master/docs/reference.md) to retrieve logs, according to a user-defined schedule. Each activation instance is decoded to an event and forwarded into the system.

This plugin is based off [logstash-input-http_poller](https://github.com/logstash-plugins/logstash-input-http_poller).

## Config Example

```
input {
  openwhisk {
    # Mandatory Configuration Parameters
    hostname => "openwhisk.ng.bluemix.net"
    username => "sample_user@email.com"
    password => "some_password"
    # Supports "cron", "every", "at" and "in" schedules by rufus scheduler
    schedule => { "every" => "15m"}

    # Optional Configuration Parameters
    # Namespace is optional, defaults to user's default namespace.
    namespace => ""
    request_timeout => 60
    codec => "json"
    # A hash of request metadata info (timing, response headers, etc.) will be sent here
    metadata_target => "http_poller_metadata"
  }
}

output {
  stdout {
    codec => rubydebug
  }
}
```

For configuration documentation, see `openwhisk.rb` in `lib/logstash/inputs/` in this repo.

This plugin uses the [Rufus scheduler](https://github.com/jmettraux/rufus-scheduler) to manage the polling request schedule. The `schedule` parameter is parsed by this module and supports all the valid scheduling directives.

More configuration files using this plugin are available in `examples`.

## Installation

`$ bin/logstash-plugin install logstash-input-openwhisk`

## Docker Example

See the `examples/docker` folder for details on building a Docker image for the Elasticsearch, Logstash and Kibaba with the Openwhisk plugin installed.

## Need Help?

Feel free to raise an issue on this project, add a question on [Stack Overflow](http://stackoverflow.com/questions/tagged/openwhisk) or come and talk to us in the [OpenWhisk Slack channel](https://developer.ibm.com/openwhisk/2016/06/15/talk-to-us-on-slack/).

## Developing

### 1. Plugin Developement and Testing

#### Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Create a new plugin or clone and existing from the GitHub [logstash-plugins](https://github.com/logstash-plugins) organization. We also provide [example plugins](https://github.com/logstash-plugins?query=example).

- Install dependencies
```sh
bundle install
```

#### Test

- Update your dependencies

```sh
bundle install
```

- Run tests

```sh
bundle exec rspec
```

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-input-openwhisk", :path => "/your/local/logstash-input-openwhisk"
```
- Install plugin
```sh
# Logstash 2.3 and higher
bin/logstash-plugin install --no-verify

# Prior to Logstash 2.3
bin/plugin install --no-verify

```
- Run Logstash with your plugin
```sh
bin/logstash -e 'input {openwhisk {...}}'
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-input-openwhisk.gemspec
```
- Install the plugin from the Logstash home
```sh
# Logstash 2.3 and higher
bin/logstash-plugin install --no-verify

# Prior to Logstash 2.3
bin/plugin install --no-verify

```
- Start Logstash and proceed to test the plugin
