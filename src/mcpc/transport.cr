require "http/client"
require "http/headers"
require "uri"
require "json"

module MCPC
  class UnsupportedTransportError < Exception
    # getter details : Transport::ErrorDetails

    # def initialize(message), @details)
    #   super(message)
    # end
  end

  # Base MCP protocol transport, with some helpers
  abstract class Transport
    alias ErrorDetails = Hash(String, String | JSON::Any)

    HEADERS = HTTP::Headers{
      "Content-Type" => "application/json",
      "Accept"       => ["application/json", "text/event-stream"],
      "User-Agent"   => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:141.0) Gecko/20100101 Firefox/141.0",
    }

    # Control network traffic tracing sent to STDERR
    property? tracing = false

    # Send a request. Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response.
    abstract def post(body, & : JSON::Any | ErrorDetails ->)

    # Send a notification. Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response.
    abstract def notify(body, & : JSON::Any | ErrorDetails ->)

    # Interprets the response line by line per the SSE spec and return
    # a `Hash` of name/value pairs.
    private def extract_sse_event(io) : Hash(String, String)
      message = {} of String => String
      # Rules below are from the SSE specification
      # https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
      STDERR.puts("~~ MCP (#{self.class}) ##extract_sse_event").colorize(:cyan) if tracing?
      io.each_line do |line|
        STDERR.puts("~~    #{line}").colorize(:cyan) if tracing?
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
      STDERR.puts("~~    return #{message}").colorize(:cyan) if tracing?
      message
    end

    # Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response. Called
    private def handle_sse_response(resp, skip_to_end = true, & : JSON::Any | ErrorDetails ->)
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
            "request_headers"  => JSON.parse(last_request_headers.to_json),
            "response_status"  => "#{resp.status_code} #{resp.status}",
            "response_headers" => JSON.parse(resp.headers.to_json),
            "response_body"    => io.gets_to_end,
          }
        end
      ensure
        io.skip_to_end if skip_to_end
      end
    end

    private def trace_response(resp, label = self.class.name, req_body = nil)
      return unless tracing?
      STDERR.puts "~~ MCP (#{label}) response #{resp.status_code} #{resp.status}".colorize(:blue)
      resp.headers.each do |k, v|
        STDERR.puts "~~    < #{k}: #{v}".colorize(:blue)
      end
      STDERR.puts "~~    #{req_body}".colorize(:blue) if req_body
      STDERR.puts "~~~~~~~~~~~".colorize(:blue)
    end

    private def trace_request(req, label = self.class.name)
      return unless tracing?
      STDERR.puts "~~ MCP (#{label}) request #{req.method} #{req.hostname} #{req.path}".colorize(:magenta)
      req.headers.each do |k, v|
        STDERR.puts "~~    > #{k}: #{v}".colorize(:magenta)
      end
    end
  end
end
