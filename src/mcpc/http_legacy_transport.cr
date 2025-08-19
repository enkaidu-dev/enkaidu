require "http/client"
require "http/headers"
require "uri"
require "json"

require "./transport"

module MCPC
  # MCP HTTP Legacy transport which uses two connections, a GET to receive and a POST to send.
  class HttpLegacyTransport < Transport
    getter uri : URI
    getter mcp_session_id : String? = nil
    property mcp_protocol_version : String? = nil

    private getter last_request_headers : HTTP::Headers? = nil

    # This is the path used to POST requests to a session. This is obtained
    # by initiating the GET request
    private getter session_path : String
    private getter httpc_recv_resp : HTTP::Client::Response

    def initialize(url : String | URI, tracing = false, auth_token = nil)
      super(tracing: tracing, auth_token: auth_token)
      @uri = url.is_a?(URI) ? url : URI.parse(url)
      # Setup the GET connection
      @httpc_recv = HTTP::Client.new(uri)
      @httpc_recv.before_request do |request|
        trace_request(request, trace_label("#initialize")) if tracing?
      end
      # Check if this is legacy or not
      setup_result = setup_receiver_response
      raise UnsupportedTransportError.new("Not a legacy SSE server.") unless setup_result
      # Legacy it is
      trace_message("Legacy SSE!", label: trace_label("#initialize")) if tracing?
      @httpc_recv_resp = setup_result[:resp] # Setup the POST connection
      @session_path = setup_result[:path]
      @httpc_send = HTTP::Client.new(uri)
      @httpc_send.before_request do |request|
        # Remember
        @last_request_headers = request.headers
        trace_request(request) if tracing?
      end
    end

    private def reset_sender
      @httpc_send = HTTP::Client.new(uri)
      @httpc_send.before_request do |request|
        # Remember
        @last_request_headers = request.headers
      end
    end

    private def setup_receiver_response
      @httpc_recv.get(uri.path, prepare_request_headers) do |resp|
        trace_response(resp, label: trace_label("#setup_receiver_response")) if tracing?
        if ctype = resp.content_type
          case resp.status_code
          when 405
            if ctype.starts_with?("application/json")
              result = JSON.parse(resp.body_io.gets_to_end)
              if result["jsonrpc"]? && result.dig?("error", "code") == -32000
                # This is an HTTP+Streamable protocol
                return nil
              end
            end
          when 200
            if ctype.starts_with?("text/event-stream")
              message = find_sse_event_after_skipping_spuriosa(resp.body_io)

              if message["event"] == "endpoint"
                # This is a legacy SSE protocol; keep the response.
                return {resp: resp, path: message["data"]}
              end
            end
          end
        end
      end
    rescue ex
      if tracing?
        STDERR.puts "~~   #{ex.class}: #{ex}".colorize(:red)
        STDERR.puts ex.inspect_with_backtrace
      end
    ensure
      nil
    end

    OK_STATUS = [200, 202]

    # With the legacy transport tool calling posts seem to fail and require
    # a new sending client instance.
    private def retryable_post(body, & : JSON::Any | ErrorDetails ->)
      @httpc_send.post(session_path, prepare_request_headers, body: body) do |resp|
        trace_response(resp, label: trace_label("#retryable_post"), req_body: body) if tracing?
        if OK_STATUS.includes? resp.status_code
          handle_sse_response(@httpc_recv_resp, legacy_sse: true, skip_to_end: false) do |message|
            if message.is_a? Transport::ErrorDetails
              message["request_body"] = JSON.parse(body)
            end
            yield message
          end
        end
        resp.body_io.skip_to_end
      end
    end

    # Send a request. Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response. Listens for exception and retries the post with a new
    # HTTP client exactly once.
    def post(body, & : JSON::Any | ErrorDetails ->)
      begin
        retryable_post(body) { |result| yield result }
      rescue
        reset_sender
        retryable_post(body) { |result| yield result }
      end
    end

    # Like #post but used to send notifications without expecting any reply.
    # This matters in the legacy transport.
    def notify(body, & : JSON::Any | ErrorDetails ->)
      @httpc_send.post(session_path, prepare_request_headers, body: body) do |resp|
        trace_response(resp, label: trace_label("#notify"), req_body: body) if tracing?
        unless OK_STATUS.includes? resp.status_code
          yield Hash{
            "type"             => "error",
            "request_headers"  => JSON.parse(last_request_headers.to_json),
            "response_status"  => "#{resp.status_code} #{resp.status}",
            "response_headers" => JSON.parse(resp.headers.to_json),
            "response_body"    => resp.body_io.gets_to_end,
          }
        end
        resp.body_io.skip_to_end
      end
    end
  end
end
