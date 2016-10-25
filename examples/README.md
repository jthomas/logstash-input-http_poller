# Example Logstash Configuration

These files contain sample configuration for using the OpenWhisk input plugin with Logstash. 

The `openwhisk.conf` file is configured to index all the logs into Elasticsearch running on localhost.

The `testing.conf` file is configured to dump all the logs to stdout, this is useful for testing and debugging issues with the plugin.

Check out the [instructions for the HTTP Input Poller Plugin](https://github.com/logstash-plugins/logstash-input-http_poller#developing) for details on using this plugin in development.