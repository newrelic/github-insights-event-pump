require 'bundler'
Bundler.setup
require 'json'
require 'awesome_print'
require 'faraday'
class Pump
  def initialize
    @http = Faraday.new
    @last = 0
  end

  def run
    5.times do
      fetch "https://api.github.com/events"
      sleep 5
    end

  end

  def fetch(url)
    resp = @http.get url
    payload = JSON.parse resp.body
    dup = 0
    while (event = payload.pop) do
      id = event['id'].to_i
      if (id <= @last)
        dup += 1
        next
      end
      @last = id
      process event
    end
    puts "skipped #{dup} duplicates from last request"
    puts "remaining until cutoff: #{resp.headers['x-ratelimit-remaining']}"
    puts "reset in #{(resp.headers['x-ratelimit-reset'].to_i - Time.now.to_i)/60} minutes"
  end

  def process(event)
    puts "#{event['id']} : #{event['type']} - #{event['actor']['url']}"
  end

end

if __FILE__ == $0

Pump.new.run

end

