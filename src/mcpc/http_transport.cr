require "http/client"
require "http/headers"
require "uri"
require "json"

module MCPC
  # MCP HTTP Transport, with support streaming events
  class HttpTransport
    HEADERS = HTTP::Headers{
      "Content-Type" => "application/json",
      "Accept"       => ["application/json", "text/event-stream"],
      "User-Agent"   => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:141.0) Gecko/20100101 Firefox/141.0",
    }

    getter uri : URI
    getter mcp_session_id : String? = nil
    property mcp_protocol_version : String? = nil

    private getter last_request_headers : HTTP::Headers? = nil

    def initialize(url : String | URI, timeout_seconds = 5)
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
      set_timeout(seconds: timeout_seconds)
    end

    private def set_timeout(seconds)
      # @httpc.read_timeout = Time::Span.new(seconds: seconds) if seconds.positive?
    end

    # Interprets the response line by line per the SSE spec and return
    # a `Hash` of name/value pairs.
    private def extract_sse_event(io) : Hash(String, String)
      message = {} of String => String
      # Rules below are from the SSE specification
      # https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
      io.each_line do |line|
        # If the line starts with a U+003A COLON character (:)
        #     Ignore the line.
        next if line.starts_with?(':')
        # If the line is empty (a blank line)
        #     Dispatch the event, as defined below.
        break if line.blank?
        # If the line contains a U+003A COLON character (:)
        #     Collect the characters on the line before the first U+003A COLON character (:),
        #       and let field be that string.
        #     Collect the characters on the line after the first U+003A COLON character (:),
        #       and let value be that string. If value starts with a U+0020 SPACE character, remove it from value.
        pair = line.split(':', limit: 2)
        left = pair.first.strip
        right = pair.last.strip
        if left.blank?
          # Otherwise, the string is not empty but does not contain a U+003A COLON character (:)
          #     Process the field using the steps described below, using the whole line as the field name,
          #       and the empty string as the field value.
          left = right
          right = ""
        end
        message[left] = right
      end
      message
    end

    alias ErrorDetails = Hash(String, String | JSON::Any)

    # Send a request. Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response. Expect an `IO::TimeoutError` when the server gets stuck, in which case you'll need to
    # start a new transport/session pair.
    def post(body, timeout_seconds = -1, & : JSON::Any | ErrorDetails ->)
      set_timeout(timeout_seconds)
      @httpc.post(uri.path, HEADERS, body: body) do |resp|
        io = resp.body_io
        ok = false
        begin
          # Remember and reuse the MCP session ID
          resp.headers.each do |key, value|
            if key.downcase == "mcp-session-id"
              @mcp_session_id = value.first
              break
            end
          end
          # Use content type to determine how to process response
          # Currently we only support HTTP + Streaming
          if ct = resp.content_type
            case ct
            when .starts_with?("text/event-stream")
              message = extract_sse_event(io)
              # If the field name is "event"
              #     Set the event type buffer to the field value.
              # If the field name is "data"
              #     Append the field value to the data buffer, then append a single U+000A LINE FEED (LF) character to the data buffer.
              if message["event"] == "message" && (data = message["data"])
                # NOTE: We currently only support one data: per event:
                # NOTE: We currently ignore id: and retry:
                yield JSON.parse(data)
                ok = true
              end
            when .starts_with?("application/json")
              if data = io.gets_to_end
                yield JSON.parse(data)
                ok = true
              end
            end
          end
          if !ok
            # Unknown response for many possible reasons
            yield Hash{
              "type"             => "error",
              "request_body"     => JSON.parse(body),
              "request_headers"  => JSON.parse(last_request_headers.to_json),
              "response_status"  => "#{resp.status_code} #{resp.status}",
              "response_headers" => JSON.parse(resp.headers.to_json),
              "response_body"    => io.gets_to_end,
            }
          end
        ensure
          io.skip_to_end
        end
      end
    end
  end
end
