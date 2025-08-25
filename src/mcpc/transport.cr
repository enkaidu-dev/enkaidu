require "http/client"
require "http/headers"
require "uri"
require "json"

module MCPC
  alias AuthToken = SensitiveData(String)

  class UnsupportedTransportError < Exception
  end

  # Base MCP protocol transport, with some helpers
  abstract class Transport
    alias ErrorDetails = Hash(String, String | JSON::Any)

    private SENSITIVE_ = "<SENSITIVE / MASKED>"

    private HEADERS_GET_ = HTTP::Headers{
      "Accept"          => "text/event-stream",
      "Accept-Language" => "en-CA,en-US;q=0.7,en;q=0.3",
      "Content-Type"    => "application/json",
      "Connection"      => "keep-alive",
      "User-Agent"      => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:141.0) Gecko/20100101 Firefox/141.0",
    }

    private HEADERS_POST_ = HTTP::Headers{
      "Accept"          => "application/json, text/event-stream",
      "Accept-Language" => "en-CA,en-US;q=0.7,en;q=0.3",
      "Content-Type"    => "application/json",
      "Connection"      => "keep-alive",
      "User-Agent"      => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:141.0) Gecko/20100101 Firefox/141.0",
    }

    @last_request_headers : HTTP::Headers? = nil

    private getter auth_token : AuthToken?

    def initialize(@tracing = false, @auth_token = nil); end

    # Return headers, incorporate auth token if any
    private def prepare_request_headers
      h = HEADERS_POST_
      if bearer_auth = auth_token
        h = h.dup
        h.add("Authorization", "Bearer #{bearer_auth.sensitive_data}")
      end
      h
    end

    # Return headers, incorporate auth token if any
    private def prepare_get_request_headers
      h = HEADERS_GET_
      if bearer_auth = auth_token
        h = h.dup
        h.add("Authorization", "Bearer #{bearer_auth.sensitive_data}")
      end
      h
    end

    private def set_last_request_headers(headers : HTTP::Headers)
      @last_request_headers = headers
    end

    # Custom getter to ensure we don't put auth token when tracing
    private def last_request_headers : HTTP::Headers?
      # If we have headers, and we have a Bearer token,
      # shallow copy and sanitize and hold on to that.
      # Future calls will not find "Bearer"
      if h = @last_request_headers
        if auth = h.get?("Authorization")
          if auth.any? &.index("Bearer")
            h = h.dup
            h["Authorization"] = SENSITIVE_ # sanitize
            @last_request_headers = h       # replace
          end
        end
      end
      @last_request_headers
    end

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
      STDERR.puts("~~ MCP (#{self.class}) #extract_sse_event") if tracing?
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
        # HACK - ignore spurious responses (for now? forever? oh, I wish.)
        #        so that we get an empty Hash
        # if left.blank?
        #   # Otherwise, the string is not empty but does not contain a U+003A COLON character (:)
        #   #     Process the field using the steps described below, using the whole line as the field name,
        #   #       and the empty string as the field value.
        #   left = right
        #   right = ""
        # end
        message[left] = right unless left.blank?
      end
      STDERR.puts("~~    return #{message}") if tracing?
      message
    end

    # For legacy SSE transport only
    private def find_sse_event_after_skipping_spuriosa(io, wait_time_ms = -1) : Hash(String, String)
      # HACK to see this is even a solution for dealing with spurious records that build up
      #     because of the legacy protocol's behaviour.
      #     This should skip Empty and Ping responses
      # WARNING
      #     we might get real notifications here but I'll
      #     fight that dragon later
      message = nil
      start = Time.monotonic
      while message.nil? || message.empty?
        STDERR.puts "~~    skipping empty SSE message".colorize(:yellow) if tracing? && message
        message = extract_sse_event(io)
        if data = message["data"]?
          if data.index("\"ping\"") || data.index("\"notification/")
            # skip these also
            STDERR.puts "~~    skipping SSE message: #{data.inspect}".colorize(:yellow) if tracing?
            message = nil
          end
        end
        break if wait_time_ms.positive? && (Time.monotonic - start).total_milliseconds > wait_time_ms
      end
      message || {} of String => String
    end

    # Yields a `JSON::Any` for valid data: in the response, or `ErrorDetails` for unknown
    # response. Called
    private def handle_sse_response(resp, legacy_sse = false, skip_to_end = true, & : JSON::Any | ErrorDetails ->)
      trace_message("start", label: trace_label("handle_sse_response")) if tracing?
      io = resp.body_io
      ok = false
      begin
        unless legacy_sse
          # Remember and reuse the MCP session ID
          resp.headers.each do |key, value|
            if key.downcase == "mcp-session-id"
              @mcp_session_id = value.first
              break
            end
          end
        end
        # Use content type to determine how to process response
        # Currently we only support HTTP + Streaming
        if ct = resp.content_type
          case ct
          when .starts_with?("text/event-stream")
            message = if legacy_sse
                        find_sse_event_after_skipping_spuriosa(io)
                      else
                        extract_sse_event(io)
                      end

            # If the field name is "event"
            #     Set the event type buffer to the field value.
            # If the field name is "data"
            #     Append the field value to the data buffer, then append a single U+000A LINE FEED (LF) character to the data buffer.
            type = message["event"]? || "message"
            if type == "message" && (data = message["data"])
              # NOTE: We currently only support one data: per event:
              # NOTE: We currently ignore id: and retry:
              event = JSON.parse(data)
              trace_message("yield #{event.as_h}", label: trace_label("handle_sse_response")) if tracing?
              yield event
              ok = true
            end
          when .starts_with?("application/json")
            if data = io.gets_to_end
              yield JSON.parse(data) unless data.blank?
              ok = true
            end
          else
            trace_message("Unexpected content type: #{ct}", label: trace_label("handle_sse_response")) if tracing?
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

    private def trace_label(method)
      "#{self.class.name}#{method.starts_with?('#') ? "" : "#"}#{method}"
    end

    private def trace_message(message, label = self.class.name)
      return unless tracing?
      STDERR.puts "~~ MCP (#{label}) \"#{message}\"".colorize(:yellow)
    end

    private def trace_response(resp, label = self.class.name, req_body = nil)
      return unless tracing?
      STDERR.puts "~~ MCP request body: #{req_body}".colorize(:blue) if req_body
      STDERR.puts "~~ MCP (#{label}) response #{resp.status_code} #{resp.status}".colorize(:blue)
      resp.headers.each do |k, v|
        STDERR.puts "~~    < #{k}: #{v}".colorize(:blue)
      end
      STDERR.puts "~~~~~~~~~~~".colorize(:blue)
    end

    private def trace_request(req, label = self.class.name)
      return unless tracing?
      STDERR.puts "~~ MCP (#{label}) request #{req.method} #{req.hostname} #{req.path}".colorize(:magenta)
      req.headers.each do |k, v|
        v = SENSITIVE_ if v.any? &.index("Bearer")
        STDERR.puts "~~    > #{k}: #{v}".colorize(:magenta)
      end
    end
  end
end
