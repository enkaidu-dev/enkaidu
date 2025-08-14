require "http/client"
require "http/headers"
require "uri"
require "json"

require "./transport"

module MCPC
  # MCP HTTP modern transport that uses a single POST connection to carry request and responses
  class HttpTransport < Transport
    getter uri : URI
    getter mcp_session_id : String? = nil
    property mcp_protocol_version : String? = nil

    private getter last_request_headers : HTTP::Headers? = nil

    private getter session_path : String? = nil

    def initialize(url : String | URI)
      @uri = url.is_a?(URI) ? url : URI.parse(url)
      @httpc = HTTP::Client.new(@uri)
      @httpc.before_request do |request|
        if tmp = @mcp_session_id
          request.headers["mcp-session-id"] = tmp
        end
        if tmp = @mcp_protocol_version
          request.headers["mcp-protocol-version"] = tmp
        end
        # Remember
        @last_request_headers = request.headers
      end
    end

    # Send a request. Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response.
    def post(body, & : JSON::Any | ErrorDetails ->)
      @httpc.post(uri.path, HEADERS, body: body) do |resp|
        handle_sse_response(resp) do |message|
          if message.is_a? Transport::ErrorDetails
            message["request_body"] = JSON.parse(body)
          end
          yield message
        end
      end
    end

    def notify(body, & : JSON::Any | ErrorDetails ->)
      post body do |msg|
        yield msg
      end
    end
  end
end
