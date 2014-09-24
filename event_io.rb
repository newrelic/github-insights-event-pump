class EventIO

  attr_reader :config, :event_queue, :http, :reset_in, :requests_remaining

  def initialize(config)
    @config = config
    @event_queue = Queue.new
    @http = Faraday.new
    @requests_remaining = 5000
  end

  def github_get url
    print "."
    resp = http.get url, {}, 'Authorization' => "token #{config['token']}"
    if resp.status == 404
      raise "Commit not found: #{url}"
    elsif resp.status != 200
      raise "Problem with request: #{resp.inspect}"
    end
    # ap resp.headers
    @requests_remaining = resp.headers['x-ratelimit-remaining'].to_i
    @reset_in = resp.headers['x-ratelimit-reset'].to_i - Time.now.to_i
    return JSON.parse resp.body
  end

  def run_send_loop
    Thread.new do
        event_buffer = []
        while(true) do
          begin
            while (event_buffer.size < 100) do
              event_buffer << event_queue.pop
            end
            flush event_buffer
          rescue => e
            $stderr.puts "#{e}: #{e.backtrace.join("\n  ")}"
          end
        end
    end
  end

  private

  def flush event_buffer
    if $dryrun
      puts "Would send #{event_buffer.size} events."
    else
      resp = @http.post "https://insights-collector.newrelic.com/v1/accounts/#{config['account']}/events",
             event_buffer.to_json,
            'X-Insert-Key' => config['insert_key']
      # puts "headers:"
      # ap resp.headers
      # puts "\n"
      if resp.status == 200
        print '+'
      else
        $stderr.puts "Error sending #{event_buffer.size} events to insights, status=#{resp.status}\nBody: #{resp.body}"
        $stderr.puts "Payload: "
        ap event_buffer.inspect
      end
    end
  rescue
    event_buffer.clear
    raise
  end
end
