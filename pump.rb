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
      last_request = Time.now.to_f
      begin
        download_activity
      rescue => e
        $stderr.puts "#{e}: #{e.backtrace.join("\n   ")}"
      end
      if @event_io.requests_remaining <= 0
        puts "Reached request limit.  Sleeping #{@event_io.reset_in/60} minutes...."
        sleep @event_io.reset_in
      else
        interval = (last_request + config['interval']) - Time.now.to_f
        sleep interval if interval > 0
      end
    end
  end

  def download_activity
    payload = @event_io.github_get "https://api.github.com/events"
    next_first = payload.last['id'].to_i
    dup = 0
    @last ||= 0
    print "  "
    processed = 0
    while (github_event = payload.pop) do
      id = github_event['id'].to_i
      if (id <= @last)
        dup += 1
        next
      end
      @processor.process github_event
      processed += 1
    end
    msg = []
    msg << "#{Time.now.strftime "%D %H:%M:%S"}"
    msg << "#{processed} events"
    msg << "remaining: #{@event_io.requests_remaining}"
    msg << "in queue: #{@processor.commit_queue_length}"
    msg << "out queue: #{@event_io.event_queue.size}"
    msg << "reset in #{@event_io.reset_in/60} min"
    msg << "#{dup} dups" if dup > 0
    msg << "id gap #{next_first - @last - 1}" if next_first > @last
    puts "\n#{msg.join(";\t")}"
    @last = id.to_i if id
  end
end

if __FILE__ == $0
  if ARGV[0] == "-n"
    $dryrun = true
    puts "DRY RUN"
  end
  Pump.new(YAML.load(File.read("./config.yml"))).run
end

