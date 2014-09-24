$LOAD_PATH.unshift File.expand_path "..", __FILE__
require 'bundler'
Bundler.setup
require 'json'
require 'awesome_print'
require 'faraday'
require 'yaml'
require 'payload_processor'
require 'event_io'
require 'payload_utils'

class Pump
  include PayloadUtils

  attr_reader :config

  def initialize(config)
    @last = 0
    raise "Need config 'token'" unless config['token']
    raise "Need config 'interval'" unless config['interval']
    raise "Need config 'account'" unless config['account']
    raise "Need config 'insert_key'" unless config['insert_key']
    @config = config
    @event_io = EventIO.new config
    @processor = PayloadProcessor.new config, @event_io.event_queue
  end

  def run
    @event_io.run_send_loop

    while (true) do
      last_request = Time.now.to_i
      begin
        download_activity
#      rescue => e
#        $stderr.puts e
      end
      if @event_io.requests_remaining <= 0
        puts "Reached request limit.  Sleeping #{@event_io.reset_in/60} minutes...."
        sleep @event_io.reset_in
      else
        interval = (last_request + config['interval']) - Time.now.to_i
        sleep interval if interval > 0
      end
    end
  end

  def download_activity
    payload = @event_io.github_get "https://api.github.com/events"
    puts "\n#{Time.now.strftime "%D %H:%M:%S"}: processing #{payload.length} github events..."
    if @last && payload.last['id'].to_i > @last
      puts "  missed up to #{payload.last['id'].to_i - @last - 1} events."
    end
    dup = 0
    @last ||= 0
    print "  "
    while (github_event = payload.pop) do
      id = github_event['id'].to_i
      if (id <= @last)
        dup += 1
        next
      end
      @processor.process github_event
    end
    @last = id.to_i
    puts ""
    puts "  skipped #{dup} duplicates from last request" if dup > 0
    puts "  remaining until cutoff: #{@event_io.requests_remaining}"
    puts "  reset in #{@event_io.reset_in/60} minutes"
  end
end

if __FILE__ == $0
  if ARGV[0] == "-n"
    $dryrun = true
    puts "DRY RUN"
  end
  Pump.new(YAML.load(File.read("./config.yml"))).run
end

