$LOAD_PATH.unshift File.expand_path "..", __FILE__
require 'bundler'
Bundler.setup
require 'json'
require 'awesome_print'
require 'faraday'
require 'yaml'
require 'payload_processor'
require 'http_util'

class Pump
  include PayloadProcessor
  include HttpUtil
  attr_reader :config

  def initialize(config)
    @last = 0
    raise "Need config 'token'" unless config['token']
    raise "Need config 'interval'" unless config['interval']
    raise "Need config 'account'" unless config['account']
    raise "Need config 'insert_key'" unless config['insert_key']
    @config = config
  end

  def run
    while (true) do
      last_request = Time.now.to_i
      begin
        download_activity
#      rescue => e
#        $stderr.puts e
      end
      if @requests_remaining <= 0
        puts "Reached request limit.  Sleeping #{@reset_in/60} minutes...."
        sleep @reset_in
      else
        interval = (last_request + config['interval']) - Time.now.to_i
        sleep interval if interval > 0
      end
    end
  end

  def download_activity
    payload = get "https://api.github.com/events"
    puts "\n#{Time.now.strftime "%D %H:%M:%S"}: processing #{payload.length} github events..."
    if @last && payload.first['id'].to_i > @last
      puts "  missed up to #{payload.first['id'].to_i - @last - 1} events."
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
      process github_event
    end
    @last = id
    puts ""
    puts "  skipped #{dup} duplicates from last request" if dup > 0
    puts "  remaining until cutoff: #{@requests_remaining}"
    puts "  reset in #{@reset_in/60} minutes"
  end
end

if __FILE__ == $0
  Pump.new(YAML.load(File.read("./config.yml"))).run
end

