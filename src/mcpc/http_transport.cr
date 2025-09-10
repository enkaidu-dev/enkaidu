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

    private getter session_path : String? = nil

    def initialize(url : String | URI, tracing = false, auth_token = nil)
      super(tracing: tracing, auth_token: auth_token)
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
        set_last_request_headers request.headers
        trace_request(request) if tracing?
      end
    end

    # Send a request. Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response.
    def post(body, & : JSON::Any | ErrorDetails ->)
      @httpc.post(uri.path, prepare_request_headers, body: body) do |resp|
        trace_response(resp, label: trace_label("#post"), req_body: body) if tracing?
        handle_sse_response(resp) do |message|
          if message.is_a? Transport::ErrorDetails
            message["request_body"] = JSON.parse(body)
          end
          yield message
        end
        resp
      end
    end

    def notify(body, & : JSON::Any | ErrorDetails ->)
      trace_message("redirect to ##post", label: trace_label("#notify")) if tracing?
      post body do |msg|
        yield msg
      end
    end
  end
end
