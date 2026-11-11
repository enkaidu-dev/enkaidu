require "../../../spec_helper"

private class HttpGetSpecRunner < Tools::Web::HttpGetWebPageTool::Runner
  getter requests = [] of {String, String?}
  getter bodies = [] of IO::Memory
  property responses = [] of {Int32, String?, String}

  def get_for_spec(url, headers, &block : HTTP::Client::Response -> T) : T forall T
    http_get(url, headers) { |response| yield response }
  end

  protected def get_response(url, headers, &)
    @requests << {url, headers["X-Test"]?}
    raise "Unexpected HTTP request" if @requests.size > @responses.size

    status, location, body = @responses[@requests.size - 1]
    response_headers = HTTP::Headers.new
    response_headers["Location"] = location if location
    io = IO::Memory.new(body)
    @bodies << io
    begin
      yield HTTP::Client::Response.new(status, headers: response_headers, body_io: io)
    ensure
      io.close
    end
  end
end

Spectator.describe Tools::Web::HttpGet::BaseRunner do
  include WebToolSpecHelpers

  let(:runner) { HttpGetSpecRunner.new(Tools::Web::HttpGetWebPageTool.new(WebToolTestRenderer.new, web_tool_settings)) }

  it "yields non-redirect statuses once and returns the block value while the body is readable" do
    [200, 302, 404, 500].each do |status|
      runner.requests.clear
      runner.bodies.clear
      runner.responses = [{status, nil, "body-#{status}"}] of {Int32, String?, String}
      yields = 0
      result = runner.get_for_spec("http://example.test/", HTTP::Headers.new) do |response|
        yields += 1
        "#{response.status_code}:#{response.body_io.gets_to_end}"
      end
      expect(result).to eq("#{status}:body-#{status}")
      expect(yields).to eq(1)
      expect(runner.requests.size).to eq(1)
      expect(runner.bodies.all?(&.closed?)).to be_true
    end
  end

  it "follows 301, 307 and 308 redirects, preserving headers and yielding only the final response" do
    [301, 307, 308].each do |status|
      runner.requests.clear
      runner.bodies.clear
      runner.responses = [{status, "http://example.test/final", ""}, {200, nil, "done"}]
      yields = 0
      result = runner.get_for_spec("http://example.test/#{status}", HTTP::Headers{"X-Test" => "kept"}) do |response|
        yields += 1
        response.body_io.gets_to_end
      end
      expect(result).to eq("done")
      expect(yields).to eq(1)
      expect(runner.requests).to eq([{"http://example.test/#{status}", "kept"}, {"http://example.test/final", "kept"}])
      expect(runner.bodies.all?(&.closed?)).to be_true
    end
  end

  it "stops after three redirects without yielding" do
    runner.responses = Array({Int32, String?, String}).new(3) { {301, "http://example.test/loop", ""} }
    yields = 0
    expect do
      runner.get_for_spec("http://example.test/loop", HTTP::Headers.new) do |response|
        yields += 1
        response.status_code
      end
    end.to raise_error(Exception, "Too many HTTP redirects; aborting")
    expect(runner.requests.size).to eq(3)
    expect(yields).to eq(0)
    expect(runner.bodies.all?(&.closed?)).to be_true
  end
end
