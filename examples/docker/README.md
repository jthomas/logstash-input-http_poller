# Docker ELK Image With OpenWhisk Support

This directory contains the Docker build and Logstash configuration files to create a Docker image for the ELK stack with the OpenWhisk Logstash Input plugin installed. 

Follow the steps below to build the image and run it locally…

## Update the configuration files

Edit `03-openwhisk-input.conf` to add your authentication credentials for the OpenWhisk platform. You can customise this input configuration to specify more properties for the plugin.

## Build the Docker image

Run the following command to build the Docker image.

`docker build -t elk_openwhisk .`

## Run the Docker container

Use the following command to start a new container from the image.

`docker run -p 5601:5601 -p 9200:9200 -p 5044:5044 -p 5000:5000 -it --name elk elk_openwhisk`

When ElasticSearch, Kibana and Logstash start, they will start outputting the startup logs to the console. Look for this line to tell you when Kibana is ready to use…

`{"type":"log","@timestamp":"2016-10-24T16:45:53Z","tags":["listening","info"],"pid":197,"message":"Server running at http://0.0.0.0:5601"}`

## Generate some OpenWhisk Logs

Use the command-line or web UI, invoke an Action or fire a Trigger a few times. This logs will be imported into the ElasticSearch index after the Logstash input plugin has been run. You can verify the logs that should be imported using the command-line utility.

`wsk activation list`

## View the logs in Kibana

Open your web browser and browse to http://localhost:5601/. 

This will open the Kibana home page.

Before you can view the logs, you need to specify which [Index](https://www.elastic.co/guide/en/elasticsearch/guide/current/index-doc.html) you want to view. We set up the OpenWhisk logs to be indexed under the 'openwhisk' index. Replace the "index" name in the input field with this value and select to confirm.

Once the index has been confirmed, you can browse to the Discover tab and see all the current logs that have been indexed. 

Isn't that cool? 😎