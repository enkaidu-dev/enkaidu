require "../../spec_helper"

private class ConnectionSpecError < Exception
end

private class ConnectionSpecConnection < LLM::Connection
  getter attempts = 0
  property failures = 0

  def protocol : LLM::ProtocolKind
    LLM::ProtocolKind::ChatCompletions
  end

  protected def url : String
    "http://127.0.0.1"
  end

  def path : String
    "/stream"
  end

  protected def headers : HTTP::Headers
    HTTP::Headers{"Content-Type" => "application/json"}
  end

  def stream(body : String, & : HTTP::Client::Response ->)
    post_and_stream(body) { |response| yield response }
  end

  private def attempt_post_and_stream(body, session_id : String? = nil, path : String? = nil, &)
    @attempts += 1
    if @attempts <= @failures
      raise IO::Error.new("synthetic stream failure")
    end

    yield HTTP::Client::Response.new(HTTP::Status::OK, body: "response-#{@attempts}")
  end
end

Spectator.describe LLM::Connection do
  describe "stream retry handling" do
    it "does not retry application exceptions raised by the stream callback" do
      connection = ConnectionSpecConnection.new

      expect do
        connection.stream("{}") do |_response|
          raise ConnectionSpecError.new("stop processing")
        end
      end.to raise_error(ConnectionSpecError)

      expect(connection.attempts).to eq(1)
    end

    it "retries one IO error and then completes successfully" do
      connection = ConnectionSpecConnection.new
      connection.failures = 1
      responses = [] of String

      connection.stream("{}") do |response|
        responses << response.body
      end

      expect(connection.attempts).to eq(2)
      expect(responses).to eq(["response-2"])
    end

    it "propagates an IO error from the retry attempt" do
      connection = ConnectionSpecConnection.new
      connection.failures = 2

      expect do
        connection.stream("{}") { |_response| }
      end.to raise_error(IO::Error)

      expect(connection.attempts).to eq(2)
    end
  end
end
