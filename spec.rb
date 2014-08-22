ENV['RACK_ENV'] = 'test'
$LOAD_PATH << File.expand_path(".")
require 'bundler'
Bundler.setup :test
require 'pump'
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)

describe 'The Github Insights Event Pump' do

  def pump
    @pump ||= Pump.new
  end

  it "should run" do
    pump.run
  end

end


