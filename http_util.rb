module HttpUtil
  def get url
    print "."
    resp = http.get url, {}, 'Authorization' => "token #{config['token']}"
    if resp.status != 200
      raise "Problem with request: #{resp.inspect}"
    end
    @requests_remaining = resp.headers['x-ratelimit-remaining'].to_i
    @reset_in = resp.headers['x-ratelimit-reset'].to_i - Time.now.to_i
    return JSON.parse resp.body
  end

  def add(event)
    raise "Invalid event: #{event.inspect}" unless event.is_a?(Hash)
    events << event
    if events.size > 10
      flush
    end
  end

  private

  def flush
    resp = @http.post "https://insights-collector.newrelic.com/v1/accounts/#{config['account']}/events",
                       events.to_json,
                      'X-Insert-Key' => config['insert_key']

    # puts "headers:"
    # ap resp.headers
    # puts "\n"
    if resp.status == 200
      print '+'
    else
      $stderr.puts "Error sending #{events.size} events to insights, status=#{resp.status}\nBody: #{resp.body}"
      $stderr.puts "Payload: "
      ap events.inspect
    end
    @events = []
  end

  def events
    @events ||= []
  end

  def http
    @http ||= Faraday.new
  end

end
