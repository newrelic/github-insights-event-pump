ENV['RACK_ENV'] = 'test'
$LOAD_PATH << File.expand_path(".")
require 'bundler'
Bundler.setup :test
require 'pump'
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

describe 'The Github Insights Event Pump' do

  it "should check config" do
    expect{ Pump.new({}) }.to raise_error RuntimeError, "Need config 'token'"
  end

  it "should fetch" do

    expected_payload = [ {
        eventType: 'GithubEvent',
        gitEventType: 'CreateEvent',
      },
      {
        eventType: 'GithubEvent',
        gitEventType: 'IssueCommentEvent',
      }
    ]
    stub_request(:get, "https://api.github.com/events").
    with(:headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Authorization'=>'xxx', 'User-Agent'=>'Faraday v0.9.0'}).
    to_return(:status => 200, :body => File.read("./fixtures/events.json"), :headers => {})

    stub_request(:post, "https://insights-collector.newrelic.com/v1/accounts//events").
    with(:body => {""=>{expected_payload.map(&:to_json).join(',')=>true}},
         :headers => {'Accept'=>'*/*', 'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', 'Content-Type'=>'application/x-www-form-urlencoded', 'User-Agent'=>'Faraday v0.9.0', 'X-Insert-Key'=>'yyy'}).
    to_return(:status => 200, :body => "", :headers => {})

    pump = Pump.new token: 'xxx', insert_key: 'yyy', interval: 10
    pump.fetch
  end

end


