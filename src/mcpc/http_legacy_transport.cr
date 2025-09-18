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

    # This is the path used to POST requests to a session. This is obtained
    # by initiating the GET request
    private getter session_path : String
    private getter httpc_recv_resp : HTTP::Client::Response

    @httpc_recv : HTTP::Client

    def initialize(url : String | URI, tracing = false, auth_token = nil)
      super(tracing: tracing, auth_token: auth_token)
      @uri = parse_url(url)

      # Setup the GET connection
      @httpc_recv = setup_receiver_client

      # Check if this is legacy or not
      setup_result = setup_receiver_response
      raise UnsupportedTransportError.new("Not a legacy SSE server.") unless setup_result

      # Legacy it is
      trace_message("Legacy SSE!", label: trace_label("#initialize")) if tracing?
      @httpc_recv_resp = setup_result[:resp]

      # Setup the POST connection
      @session_path = setup_result[:path]
      @httpc_send = setup_legacy_sender_client
    end

    # Clean up the transport and close all underlying client connections; renders
    # the transport unusable permanently
    def close
      @httpc_send.close
      @httpc_recv.close
    end

    private def parse_url(url)
      url.is_a?(URI) ? url : URI.parse(url)
    end

    private def setup_receiver_client
      receiver = HTTP::Client.new(uri)
      receiver.before_request do |request|
        trace_request(request, trace_label("#initialize")) if tracing?
      end
      receiver
    end

    private def setup_legacy_sender_client
      sender = HTTP::Client.new(uri)
      sender.before_request do |request|
        # Remember
        set_last_request_headers request.headers
        trace_request(request) if tracing?
      end
      sender
    end

    private def reset_sender
      @httpc_send = HTTP::Client.new(uri)
      @httpc_send.before_request do |request|
        # Remember for if/when we have an error to trace
        set_last_request_headers request.headers
      end
    end

    private def setup_receiver_response
      result = nil
      @httpc_recv.get(uri.path, prepare_get_request_headers) do |response|
        trace_response(response, label: trace_label("#setup_receiver_response")) if tracing?

        if content_type = response.content_type
          status_code = response.status_code
          result = handle_response_by_type_and_status(content_type, status_code, response)
        end
        response # Always return the response at end of streaming handler block
      end

      result
    rescue ex
      log_error(ex) if tracing?
    ensure
      nil
    end

    private def handle_response_by_type_and_status(content_type, status_code, response)
      case status_code
      when 200
        if content_type.starts_with?("text/event-stream")
          message = find_sse_event_after_skipping_spuriosa(response.body_io, wait_time_ms: 500)
          return {resp: response, path: message["data"]} if message["event"]? == "endpoint"
        end
      end
    end

    # private def handle_status_405(content_type, response)
    #   #
    #   # This method looks like it always returns nil.
    #   # I don't think we need to check the 405 path at all
    #   #
    #   if content_type.starts_with?("application/json")
    #     result = JSON.parse(response.body_io.gets_to_end)
    #     return nil if result["jsonrpc"]? && result.dig?("error", "code") == -32000
    #   end
    # end

    private def log_error(exception)
      STDERR.puts "~~   #{exception.class}: #{exception}".colorize(:red)
      STDERR.puts exception.inspect_with_backtrace
    end

    OK_STATUS = [200, 202]

    # Send a request. Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response. Listens for exception and retries the post with a new
    # HTTP client exactly once.
    def post(body, & : JSON::Any | ErrorDetails ->)
      @httpc_send.post(session_path, prepare_request_headers, body: body) do |resp|
        trace_response(resp, label: trace_label("#post"), req_body: body) if tracing?
        if OK_STATUS.includes? resp.status_code
          handle_sse_response(@httpc_recv_resp, legacy_sse: true, skip_to_end: false) do |message|
            if message.is_a? Transport::ErrorDetails
              message["request_body"] = JSON.parse(body)
            end
            yield message
          end
        end
        resp.body_io.skip_to_end
        resp
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
        resp
      end
    end
  end
end
