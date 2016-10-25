FROM sebp/elk

ADD 03-openwhisk-input.conf /etc/logstash/conf.d/03-openwhisk-input.conf
ADD 30-output.conf /etc/logstash/conf.d/30-output.conf

WORKDIR ${LOGSTASH_HOME}
RUN gosu logstash bin/logstash-plugin install logstash-input-openwhisk
