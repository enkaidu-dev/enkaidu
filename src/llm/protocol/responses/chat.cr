require "http"
require "json"

require "../../chat"
require "../../connection"
require "../../message/message"
require "../../history"
require "../../response_schema"
require "../../protocol_kind"
require "../../usage"

require "./encoder"
require "./decoder"
require "./function_call_builder"

module LLM::Protocol::Responses
  # The Responses-protocol `Chat` adapter. It implements the single abstract
  # contract `post_session` (encode → POST → decode → append); session
  # management and the tool loop live on the base `LLM::Chat`.
  # The request is posted to connection's path.
  class Chat < LLM::Chat
    include Encoder
    include Decoder

    @conn : Connection

    def initialize(@conn)
      super()
      @model = @conn.model
      unless @conn.protocol.responses?
        raise ArgumentError.new("Connection's protocol must be Responses, not: #{@conn.protocol}")
      end
    end

    def with_model(model : String)
      super
      @conn.model = model
    end

    # The one protocol contract: encode the current session as a Responses
    # request, POST it (SSE or JSON), yield canonical `ChatEvent`s, and append
    # the resulting `Message::Response` to history.
    def post_session(response_schema : ResponseSchema? = nil,
                     exclude_reasoning_in_history = false,
                     exclude_reasoning_skip = 0,
                     & : LLM::ChatEvent ->) : Nil
      @history.exclude_past_reasoning(skip_turns: exclude_reasoning_skip) if exclude_reasoning_in_history
      body = to_body(response_schema)

      yield({type: LLM::Event::DebugRequest, content: JSON.parse(body)}) if debug?

      STDERR.puts ">>> #{body}" if TRACE
      @conn.post_and_stream(body, session_id, path: @conn.path) do |resp|
        STDERR.puts "<<< #{resp.headers}" if TRACE
        resp_unexp = false
        case resp.status
        when .too_many_requests?
          # If we get the 429
          yield warn_too_many_requests_delay(JSON::Any.new("#{resp.status_code} #{resp.status_message}"))
          raise TooManyRequests.new(@conn.path)
        when .ok?
          case resp.content_type
          when "text/event-stream" then handle_text_event_stream(resp) { |msg| yield msg }
          when "application/json"  then handle_app_json(resp) { |msg| yield msg }
          else                          resp_unexp = true
          end
        else resp_unexp = true
        end
        # We don't know what to do if it's neither SSE nor JSON.
        yield unexpected_response(resp) if resp_unexp
      end
    end

    private def handle_text_event_stream(resp, &)
      stream_io = resp.body_io
      aggr_msg = prepare_message_from_streamed_data(stream_io) do |msg|
        yield msg
      end
      STDERR.puts "+++ #{aggr_msg.to_json}" if TRACE
      append_message aggr_msg if aggr_msg
    end

    private def handle_app_json(resp, &) : Nil
      # Read the whole body and parse it as a Responses object (or an error).
      body = resp.body_io.gets_to_end
      begin
        data = JSON.parse(body)
        # A present-but-null `error` field is *not* an error: `response`
        # objects (e.g. Ollama's) carry `"error": null` on success.
        if (err = data["error"]?) && !err.raw.nil?
          # If we get here but error says too many requests:
          yield warn_too_many_requests_delay(data)
          raise TooManyRequests.new(body) if body.includes?("too_many_request")

          yield({type: LLM::Event::ErrorServer, content: data})
        elsif dig_string(data, "object") == "response.error"
          yield({type: LLM::Event::ErrorServer, content: data})
        else
          msg = process_responses_json(data) do |emitted|
            yield emitted
          end
          append_message msg
        end
      rescue ex
        LLM.show_error_trace(ex, data_label: "body", data: body)
      end
    end

    private def unexpected_response(resp)
      {type: LLM::Event::ErrorUnexpected, content: JSON::Any.new(Hash{
        "headers" => JSON.parse(resp.headers.to_h.to_json),
        "body"    => JSON::Any.new(resp.body_io.gets_to_end),
      })}
    end

    private def to_body(response_schema : ResponseSchema? = nil)
      JSON.build do |json|
        responses_to_json(json, model, system_message,
          streaming?, @history, each_tool, reasoning,
          temperature: temperature,
          response_schema: response_schema)
      end
    end
  end
end
