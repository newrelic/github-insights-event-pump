$LOAD_PATH.unshift File.expand_path "..", __FILE__
require 'bundler'
Bundler.setup
require 'json'
require 'awesome_print'
require 'faraday'
require 'yaml'
require 'payload_processor'

class Pump
  include PayloadProcessor
  attr_reader :config

  def initialize(config)
    @http = Faraday.new
    @last = 0
    raise "Need config 'token'" unless config['token']
    raise "Need config 'interval'" unless config['interval']
    raise "Need config 'account'" unless config['account']
    raise "Need config 'insert_key'" unless config['insert_key']
    @config = config
  end

  def run
    while (true) do
      fetch
      sleep config['interval']
    end
  end

  def fetch
    url =  "https://api.github.com/events"
    resp = @http.get url, {}, 'Authorization' => "token #{config['token']}"
    if resp.status != 200
      puts "Problem with request: #{resp.inspect}"
      return
    end

    payload = JSON.parse resp.body
    dup = 0
    insights_events = []
    github_events = 0
    while (event = payload.pop) do
      id = event['id'].to_i
      if (id <= @last)
        dup += 1
        next
      end
      github_events += 1
      @last = id
      # puts "#{event['id']} : #{event['type']} - #{event['actor']['url']}"
      insights_events += process(event['payload'], nil, event['type'])
    end
    puts "#{Time.now.strftime "%D %H:%M:%S"}: processed #{github_events} github events and inserted #{insights_events.length} events into insights..."
    puts "  skipped #{dup} duplicates from last request"
    puts "  remaining until cutoff: #{resp.headers['x-ratelimit-remaining']}"
    puts "  reset in #{(resp.headers['x-ratelimit-reset'].to_i - Time.now.to_i)/60} minutes"

    if (insights_events.empty?)
      puts "Nothing in the payload!"
      return
    end
    resp = send(insights_events)
    # puts "headers:"
    # ap resp.headers
    # puts "\n"
    if resp.status == 200
      puts "Inserted #{insights_events.length} events"
    else
      $stderr.puts "Error sending to insights: #{resp.body}"
    end
  end


  def send(events)
    @http.post "https://insights-collector.newrelic.com/v1/accounts/#{config['account']}/events",
               events.to_json,
               'X-Insert-Key' => config['insert_key']
  end

end

if __FILE__ == $0
  Pump.new(YAML.load(File.read("./config.yml"))).run
end

