# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/plugin_mixins/http_client"
require "socket" # for Socket.gethostname
require "manticore"
require "rufus/scheduler"

# This Logstash input plugin allows you to drain OpenWhisk Activation logs, decoding the output into event(s), and
# send them on their merry way. Using the OpenWhisk platform API, we poll the activation logs API according to the config schedule.
# This plugin borrows heavily from the HTTP Poller input plugin. 
#
# ==== Example
# Drain logs from an OpenWhisk platform instance.
# The config should look like this:
#
# [source,ruby]
# ----------------------------------
# input {
#   openwhisk {
#     # Mandatory Configuration Parameters
#     hostname => "openwhisk.ng.bluemix.net"
#     username => "sample_user@email.com"
#     password => "some_password"
#     # Supports "cron", "every", "at" and "in" schedules by rufus scheduler
#     schedule => { cron => "* * * * * UTC"}
#
#     # Optional Configuration Parameters
#     # Namespace is optional, defaults to user's default namespace.
#     namespace => ""
#     request_timeout => 60
#     codec => "json"
#     # A hash of request metadata info (timing, response headers, etc.) will be sent here
#     metadata_target => "http_poller_metadata"
#   }
# }
#
# output {
#   stdout {
#     codec => rubydebug
#   }
# }
# ----------------------------------
#

class LogStash::Inputs::OpenWhisk < LogStash::Inputs::Base
  include LogStash::PluginMixins::HttpClient

  config_name "openwhisk"

  default :codec, "json"

  # OpenWhisk Platform Parameters
  config :hostname, :validate => :string, :required => true
  config :username, :validate => :string, :required => true
  config :password, :validate => :string, :required => true

  # Optional OpenWhisk namespace, defaults to user account namespace.
  config :namespace, :validate => :string, :default => '_'

  # How often (in seconds) the urls will be called
  # DEPRECATED. Use 'schedule' option instead.
  # If both interval and schedule options are specified, interval
  # option takes higher precedence
  config :interval, :validate => :number, :deprecated => true

  # Schedule of when to periodically poll from the urls
  # Format: A hash with
  #   + key: "cron" | "every" | "in" | "at"
  #   + value: string
  # Examples:
  #   a) { "every" => "1h" }
  #   b) { "cron" => "* * * * * UTC" }
  # See: rufus/scheduler for details about different schedule options and value string format
  config :schedule, :validate => :hash

  # Define the target field for placing the received data. If this setting is omitted, the data will be stored at the root (top level) of the event.
  config :target, :validate => :string

  # If you'd like to work with the request/response metadata.
  # Set this value to the name of the field you'd like to store a nested
  # hash of metadata.
  config :metadata_target, :validate => :string, :default => '@metadata'

  public
  Schedule_types = %w(cron every at in)
  def register
    @host = Socket.gethostname.force_encoding(Encoding::UTF_8)

    @logger.info("Registering openwhisk Input", :type => @type,
                 :hostname=> @hostname, :interval => @interval, :schedule => @schedule, :timeout => @timeout)

    # we will start polling for logs since the current epoch
    @logs_since = Time.now.to_i * 1000

    # activation ids from previous poll used to control what is indexed,
    # we might have overlapping results and don't want to index the same
    # activations twice.
    @activation_ids = Set.new
  end

  def stop
    Stud.stop!(@interval_thread) if @interval_thread
    @scheduler.stop if @scheduler
  end

  # generate HTTP request options for current platform host.
  private
  def construct_request(opts)
    url = "https://#{opts['hostname']}/api/v1/namespaces/#{opts['namespace']}/activations"
    auth = {user: opts['username'], pass: opts['password']} 
    query = {docs: true, limit: 0, skip: 0, since: @logs_since}
    res = [:get, url, {:auth => auth, :query => query}]
  end

  public
  def run(queue)
    #interval or schedule must be provided. Must be exclusively either one. Not neither. Not both.
    raise LogStash::ConfigurationError, "Invalid config. Neither interval nor schedule was specified." \
      unless @interval ||  @schedule
    raise LogStash::ConfigurationError, "Invalid config. Specify only interval or schedule. Not both." \
      if @interval && @schedule

    if @interval
      setup_interval(queue)
    elsif @schedule
      setup_schedule(queue)
    else
      #should not reach here
      raise LogStash::ConfigurationError, "Invalid config. Neither interval nor schedule was specified."
    end
  end

  private
  def setup_interval(queue)
    @interval_thread = Thread.current
    Stud.interval(@interval) do
      run_once(queue)
    end
  end

  def setup_schedule(queue)
    #schedule hash must contain exactly one of the allowed keys
    msg_invalid_schedule = "Invalid config. schedule hash must contain " +
      "exactly one of the following keys - cron, at, every or in"
    raise Logstash::ConfigurationError, msg_invalid_schedule if @schedule.keys.length !=1
    schedule_type = @schedule.keys.first
    schedule_value = @schedule[schedule_type]
    raise LogStash::ConfigurationError, msg_invalid_schedule unless Schedule_types.include?(schedule_type)

    @scheduler = Rufus::Scheduler.new(:max_work_threads => 1)
    #as of v3.0.9, :first_in => :now doesn't work. Use the following workaround instead
    opts = schedule_type == "every" ? { :first_in => 0.01 } : {} 
    @scheduler.send(schedule_type, schedule_value, opts) { run_once(queue) }
    @scheduler.join
  end

  def run_once(queue)
    request = construct_request({"hostname" => @hostname, "username" => @username, "password" => @password, "namespace" => @namespace})

    request_async(queue, "openwhisk", request)
    client.execute!
  end

  private
  def request_async(queue, name, request)
    @logger.debug? && @logger.debug("Fetching URL", :name => name, :url => request)
    started = Time.now

    method, *request_opts = request
    client.async.send(method, *request_opts).
      on_success {|response| handle_success(queue, name, request, response, Time.now - started)}.
      on_failure {|exception|
      handle_failure(queue, name, request, exception, Time.now - started)
    }
  end

  private
  def handle_success(queue, name, request, response, execution_time)
    activation_ids = Set.new

    @codec.decode(response.body) do |decoded|
      activation_id = decoded.to_hash["activationId"]

      ## ignore results we have previously seen
      if !@activation_ids.include?(activation_id)
        event = @target ? LogStash::Event.new(@target => decoded.to_hash) : decoded
        update_logs_since(decoded.to_hash["end"])
        handle_decoded_event(queue, name, request, response, event, execution_time)
      end

      activation_ids.add(activation_id)
    end

    @activation_ids = activation_ids
  end

  # updates the query parameter for the next request
  # based upon the last activation's end time.
  private
  def update_logs_since(ms_since_epoch)
    # actions have a maximum timeout for five minutes
    max_action_time_ms = 5 * 60 * 1000
    next_logs_since = ms_since_epoch - max_action_time_ms

    if (next_logs_since > @logs_since)
      @logs_since = next_logs_since
    end
  end

  private
  def handle_decoded_event(queue, name, request, response, event, execution_time)
    apply_metadata(event, name, request, response, execution_time)
    decorate(event)
    queue << event
  rescue StandardError, java.lang.Exception => e
    @logger.error? && @logger.error("Error eventifying response!",
                                    :exception => e,
                                    :exception_message => e.message,
                                    :name => name,
                                    :url => request,
                                    :response => response
    )
  end

  private
  # Beware, on old versions of manticore some uncommon failures are not handled
  def handle_failure(queue, name, request, exception, execution_time)
    event = LogStash::Event.new
    apply_metadata(event, name, request)

    event.tag("_http_request_failure")

    # This is also in the metadata, but we send it anyone because we want this
    # persisted by default, whereas metadata isn't. People don't like mysterious errors
    event.set("http_request_failure", {
      "request" => structure_request(request),
      "name" => name,
      "error" => exception.to_s,
      "backtrace" => exception.backtrace,
      "runtime_seconds" => execution_time
   })

    queue << event
  rescue StandardError, java.lang.Exception => e
      @logger.error? && @logger.error("Cannot read URL or send the error as an event!",
                                      :exception => e,
                                      :exception_message => e.message,
                                      :exception_backtrace => e.backtrace,
                                      :name => name,
                                      :url => request
      )
  end

  private
  def apply_metadata(event, name, request, response=nil, execution_time=nil)
    return unless @metadata_target
    event.set(@metadata_target, event_metadata(name, request, response, execution_time))
  end

  private
  def event_metadata(name, request, response=nil, execution_time=nil)
    m = {
        "name" => name,
        "hostname" => @hostname,
        "request" => structure_request(request),
      }

    m["runtime_seconds"] = execution_time

    if response
      m["code"] = response.code
      m["response_headers"] = response.headers
      m["response_message"] = response.message
      m["times_retried"] = response.times_retried
    end

    m
  end

  private
  # Turn [method, url, spec] requests into a hash for friendlier logging / ES indexing
  def structure_request(request)
    method, url, spec = request
    # Flatten everything into the 'spec' hash, also stringify any keys to normalize
    Hash[(spec||{}).merge({
      "method" => method.to_s,
      "url" => url,
    }).map {|k,v| [k.to_s,v] }]
  end
end
