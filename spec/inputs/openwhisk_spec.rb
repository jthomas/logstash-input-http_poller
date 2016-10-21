require "logstash/devutils/rspec/spec_helper"
require 'logstash/inputs/openwhisk'
require 'flores/random'
require "timecop"

describe LogStash::Inputs::OpenWhisk do
  let(:metadata_target) { "_openwhisk_metadata" }
  let(:queue) { Queue.new }
  let(:default_schedule) {
    { "cron" => "* * * * * UTC" }
  }
  let(:default_name) { "openwhisk" }
  let(:default_hostname) { "localhost" }
  let(:default_username) { "user@email.com" }
  let(:default_password) { "my_password" }
  let(:default_namespace) { "user_namespace" }
  let(:default_opts) {
    {
      "schedule" => default_schedule,
      "hostname" => default_hostname,
      "username" => default_username,
      "password" => default_password,
      "namespace" => default_namespace,
      "codec" => "json",
      "metadata_target" => metadata_target
    }
  }
  let(:klass) { LogStash::Inputs::OpenWhisk }

  describe "instances" do
    subject { klass.new(default_opts) }

    before do
      subject.register
    end

    describe "#register" do 
      it "should set logs since to time since epoch" do
        expect(subject.instance_variable_get("@logs_since")).to eql(Time.now.to_i * 1000)
      end
    end

    describe "#run" do
      it "should setup a scheduler" do
        runner = Thread.new do
          subject.run(double("queue"))
          expect(subject.instance_variable_get("@scheduler")).to be_a_kind_of(Rufus::Scheduler)
        end
        runner.kill
        runner.join
      end
    end

    describe "#run_once" do
      it "should issue an async request for each url" do
        constructed_request = subject.send(:construct_request, default_opts)
        expect(subject).to receive(:request_async).with(queue, default_name, constructed_request).once

        subject.send(:run_once, queue) # :run_once is a private method
      end
    end

    describe "#update_logs_since" do
      context "given current time less than five minutes ahead of last poll activation" do
        let(:now) { Time.now.to_i * 1000 }
        let(:previous) {
          now - (5 * 60 * 1000) + 1
        }
        before do
          subject.instance_variable_set("@logs_since", previous)
          subject.send(:update_logs_since, now)
        end

        it "should not update logs since" do
          expect(subject.instance_variable_get("@logs_since")).to eql(previous)
        end
      end

      context "given current time more than five minutes ahead of last poll activation" do
        let(:now) { Time.now.to_i * 1000 }
        let(:previous) {
          now - (5 * 60 * 1000) - 1
        }
        before do
          subject.instance_variable_set("@logs_since", previous)
          subject.send(:update_logs_since, now)
        end

        it "should update logs since x" do
          expect(subject.instance_variable_get("@logs_since")).to eql(now - 5 * 60 * 1000)
        end
      end
    end

    describe "constructor" do 
      context "given options missing hostname" do
        let(:opts) {
          opts = default_opts.clone
          opts.delete("hostname")
          opts
        }

        it "should raise ConfigurationError" do
          expect { klass.new(opts) }.to raise_error(LogStash::ConfigurationError)
        end
      end

      context "given options missing username" do
        let(:opts) {
          opts = default_opts.clone
          opts.delete("username")
          opts
        }

        it "should raise ConfigurationError" do
          expect { klass.new(opts) }.to raise_error(LogStash::ConfigurationError)
        end
      end
 
      context "given options missing password" do
        let(:opts) {
          opts = default_opts.clone
          opts.delete("password")
          opts
        }

        it "should raise ConfigurationError" do
          expect { klass.new(opts) }.to raise_error(LogStash::ConfigurationError)
        end
      end
 
      context "given options missing namespace" do
        let(:opts) {
          opts = default_opts.clone
          opts.delete("namespace")
          opts
        }

        it "should use default namespace" do
          instance = klass.new(opts)
          expect(instance.namespace).to eql("_")
        end
      end
 
      context "given options with namespace" do
        it "should use options namespace" do
          instance = klass.new(default_opts)
          expect(instance.namespace).to eql(default_namespace)
        end
      end
    end

    describe "construct request spec" do 
      context "with normal options" do 
        let(:result) { subject.send(:construct_request, default_opts) }

        it "should set method correctly" do 
          expect(result[0]).to eql(:get)
        end

        it "should set url correctly" do 
          expect(result[1]).to eql("https://#{default_hostname}/api/v1/namespaces/#{default_namespace}/activations")
        end

        it "should set auth correctly" do
          expect(result[2][:auth]).to eql({user: default_username, pass: default_password})
        end

        it "should set query string correctly" do
          expect(result[2][:query]).to eql({docs: true, limit: 0, skip: 0, since: subject.instance_variable_get('@logs_since')})
        end
      end
    end

    describe "#structure_request" do
      it "Should turn a simple request into the expected structured request" do
        expected = {"url" => "http://example.net", "method" => "get"}
        expect(subject.send(:structure_request, ["get", "http://example.net"])).to eql(expected)
      end

      it "should turn a complex request into the expected structured one" do
        headers = {
          "X-Fry" => " Like a balloon, and... something bad happens! "
        }
        expected = {
          "url" => "http://example.net",
          "method" => "get",
          "headers" => headers
        }
        expect(subject.send(:structure_request, ["get", "http://example.net", {"headers" => headers}])).to eql(expected)
      end
    end
  end

  describe "scheduler configuration" do
    context "given an interval" do
      let(:opts) {
        {
          "interval" => 2,
          "hostname" => default_hostname,
          "username" => default_username,
          "password" => default_password,
          "codec" => "json",
          "metadata_target" => metadata_target
        }
      }
      it "should run once in each interval" do
        instance = klass.new(opts)
        instance.register
        queue = Queue.new
        runner = Thread.new do
          instance.run(queue)
        end
        #T       0123456
        #events  x x x x
        #expects 3 events at T=5
        sleep 5
        instance.stop
        runner.kill
        runner.join
        expect(queue.size).to eq(3)
      end
    end

    context "given both interval and schedule options" do
      let(:opts) {
        {
          "interval" => 1,
          "schedule" => { "every" => "5s" },
          "hostname" => default_hostname,
          "username" => default_username,
          "password" => default_password,
          "codec" => "json",
          "metadata_target" => metadata_target
        }
      }
      it "should raise ConfigurationError" do
        instance = klass.new(opts)
        instance.register
        queue = Queue.new
        runner = Thread.new do
          expect{instance.run(queue)}.to raise_error(LogStash::ConfigurationError)
        end
        instance.stop
        runner.kill
        runner.join
      end
    end

    context "given 'cron' expression" do
      let(:opts) {
        {
          "schedule" => { "cron" => "* * * * * UTC" },
          "hostname" => default_hostname,
          "username" => default_username,
          "password" => default_password,
          "codec" => "json",
          "metadata_target" => metadata_target
        }
      }
      it "should run at the schedule" do
        instance = klass.new(opts)
        instance.register
        Timecop.travel(Time.new(2000,1,1,0,0,0,'+00:00'))
        Timecop.scale(60)
        queue = Queue.new
        runner = Thread.new do
          instance.run(queue)
        end
        sleep 3
        instance.stop
        runner.kill
        runner.join
        expect(queue.size).to eq(2)
        Timecop.return
      end
    end

    context "given 'at' expression" do
      let(:opts) {
        {
          "schedule" => { "at" => "2000-01-01 00:05:00 +0000"},
          "hostname" => default_hostname,
          "username" => default_username,
          "password" => default_password,
          "codec" => "json",
          "metadata_target" => metadata_target
        }
      }
      it "should run at the schedule" do
        instance = klass.new(opts)
        instance.register
        Timecop.travel(Time.new(2000,1,1,0,0,0,'+00:00'))
        Timecop.scale(60 * 5)
        queue = Queue.new
        runner = Thread.new do
          instance.run(queue)
        end
        sleep 2
        instance.stop
        runner.kill
        runner.join
        expect(queue.size).to eq(1)
        Timecop.return
      end
    end

    context "given 'every' expression" do
      let(:opts) {
        {
          "schedule" => { "every" => "2s"},
          "hostname" => default_hostname,
          "username" => default_username,
          "password" => default_password,
          "codec" => "json",
          "metadata_target" => metadata_target
        }
      }
      it "should run at the schedule" do
        instance = klass.new(opts)
        instance.register
        queue = Queue.new
        runner = Thread.new do
          instance.run(queue)
        end
        #T       0123456
        #events  x x x x
        #expects 3 events at T=5
        sleep 5
        instance.stop
        runner.kill
        runner.join
        expect(queue.size).to eq(3)
      end
    end

    context "given 'in' expression" do
      let(:opts) {
        {
          "schedule" => { "in" => "2s"},
          "hostname" => default_hostname,
          "username" => default_username,
          "password" => default_password,
          "codec" => "json",
          "metadata_target" => metadata_target
        }
      }
      it "should run at the schedule" do
        instance = klass.new(opts)
        instance.register
        queue = Queue.new
        runner = Thread.new do
          instance.run(queue)
        end
        sleep 3
        instance.stop
        runner.kill
        runner.join
        expect(queue.size).to eq(1)
      end
    end
  end

  describe "events" do
    shared_examples("matching metadata") {
      let(:metadata) { event.get(metadata_target) }

      it "should have the correct name" do
        expect(metadata["name"]).to eql(name)
      end

      it "should have the correct request hostname" do
        expect(metadata["hostname"]).to eql(hostname)
      end

      it "should have the correct code" do
        expect(metadata["code"]).to eql(code)
      end
    }

    shared_examples "unprocessable_requests" do
      let(:poller) { LogStash::Inputs::OpenWhisk.new(settings) }
      subject(:event) {
        poller.send(:run_once, queue)
        queue.pop(true)
      }

      before do
        poller.register
        allow(poller).to receive(:handle_failure).and_call_original
        allow(poller).to receive(:handle_success)
        event # materialize the subject
      end

      it "should enqueue a message" do
        expect(event).to be_a(LogStash::Event)
      end

      it "should enqueue a message with 'http_request_failure' set" do
        expect(event.get("http_request_failure")).to be_a(Hash)
      end

      it "should tag the event with '_http_request_failure'" do
        expect(event.get("tags")).to include('_http_request_failure')
      end

      it "should invoke handle failure exactly once" do
        expect(poller).to have_received(:handle_failure).once
      end

      it "should not invoke handle success at all" do
        expect(poller).not_to have_received(:handle_success)
      end

      include_examples("matching metadata")
    end

    context "with a non responsive server" do
      context "due to a non-existant hostname" do # Fail with handlers
        let(:name) { default_name }
        let(:hostname) { "http://thouetnhoeu89ueoueohtueohtneuohn" }
        let(:code) { nil } # no response expected

        let(:settings) { default_opts.merge("hostname" => hostname) }

        include_examples("unprocessable_requests")
      end
    end

    describe "a valid request and decoded response" do
      let(:payload) { [{"start" => 1476818509288, "end" => 1476818509888, "activationId" => "some_id", "annotations" => []}] }
      let(:opts) { default_opts }
      let(:instance) {
        klass.new(opts)
      }
      let(:name) { default_name }
      let(:code) { 202 }
      let(:hostname) { default_hostname }

      subject(:event) {
        queue.pop(true)
      }

      before do
        instance.register
        instance.instance_variable_set("@logs_since", 0)
        # match any response
        instance.client.stub(%r{.},
                             :body => LogStash::Json.dump(payload),
                             :code => code
        )
        allow(instance).to receive(:decorate)
        instance.send(:run_once, queue)
      end

      it "should have a matching message" do
        expect(event.to_hash).to include(payload[0])
      end

      it "should decorate the event" do
        expect(instance).to have_received(:decorate).once
      end

      it "should update the time since" do
        expect(instance.instance_variable_get("@logs_since")).to eql(payload[0]["end"] - (5 * 60 * 1000))
      end

      it "should retain activation ids" do
        expect(instance.instance_variable_get("@activation_ids")).to eql(Set.new ["some_id"])
      end

      include_examples("matching metadata")

      context "with metadata omitted" do
        let(:opts) {
          opts = default_opts.clone
          opts.delete("metadata_target")
          opts
        }

        it "should not have any metadata on the event" do
          instance.send(:run_once, queue)
          expect(event.get(metadata_target)).to be_nil
        end
      end

      context "with a specified target" do
        let(:target) { "mytarget" }
        let(:opts) { default_opts.merge("target" => target) }

        it "should store the event info in the target" do
          # When events go through the pipeline they are java-ified
          # this normalizes the payload to java types
          payload_normalized = LogStash::Json.load(LogStash::Json.dump(payload))
          expect(event.get(target)).to include(payload_normalized[0])
        end
      end

      context "with annotations" do
        let(:annotations) { [{"key" => "a", "value" => { "child": "val" } }, {"key" => "b", "value" => "some_string"}] }
        let(:payload) { [{"start" => 1476818509288, "end" => 1476818509888, "activationId" => "some_id", "annotations" => annotations}] }

        it "should serialise annotations to JSON strings" do
          expect(event.to_hash["annotations"]).to eql([{"key" => "a", "value" => '{"child":"val"}'}, {"key" => "b", "value" => "\"some_string\""}])
        end
      end

      context "with multiple activations" do
        let(:payload) { [{"end" => 1476818509288, "activationId" => "1", "annotations" => []},{"end" => 1476818509289, "activationId" => "2", "annotations" => []},{"end" => 1476818509287, "activationId" => "3", "annotations" => []} ] }

        it "should update logs since to latest epoch" do
          instance.instance_variable_set("@logs_since", 0)
          instance.instance_variable_set("@activation_ids", Set.new)
          instance.send(:run_once, queue)
          expect(instance.instance_variable_get("@logs_since")).to eql(payload[1]["end"] - (5 * 60 * 1000))
          expect(instance.instance_variable_get("@activation_ids")).to eql(Set.new ["1", "2", "3"])
        end
      end

      context "with previous activations" do
        let(:payload) { [{"end" => 1476818509288, "activationId" => "some_id", "annotations" => []}] }

        subject(:size) {
          queue.size()
        }
        it "should not add activation to queue" do
          instance.instance_variable_set("@activation_ids", Set.new(["some_id"]))
          queue.clear()
          instance.send(:run_once, queue)
          expect(subject).to eql(0) 
        end
      end
 
    end
  end

  describe "stopping" do
    let(:config) { default_opts }
    it_behaves_like "an interruptible input plugin"
  end
end
