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
  # management and the tool loop live on the base `LLM::Chat`. The request is
  # POSTed to the Responses path (`protocol_path`), which for a compatible
  # OpenAI/`OLLAMA_ADAPTER=responses` endpoint is `/v1/responses`.
  class Chat < LLM::Chat
    include Encoder
    include Decoder

    @conn : Connection

    def initialize(@conn)
      super()
      @model = @conn.model
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
      @conn.post_and_stream(body, session_id, path: @conn.protocol_path(LLM::ProtocolKind::Responses)) do |resp|
        STDERR.puts "<<< #{resp.headers}" if TRACE
        case resp.content_type
        when "text/event-stream" then handle_text_event_stream(resp) { |msg| yield msg }
        when "application/json"  then handle_app_json(resp) { |msg| yield msg }
        else
          # We don't know what to do if it's neither SSE nor JSON.
          yield unexpected_response(resp)
        end
      end
    end

    private def handle_text_event_stream(resp, &)
      stream_io = resp.body_io
      aggr_msg = prepare_message_from_streamed_data(stream_io) do |msg|
        yield msg
      end
      STDERR.puts "+++ #{aggr_msg.to_json}" if TRACE
      append_message aggr_msg
    end

    private def handle_app_json(resp, &) : Nil
      # Read the whole body and parse it as a Responses object (or an error).
      body = resp.body_io.gets_to_end
      begin
        data = JSON.parse(body)
        # A present-but-null `error` field is *not* an error: `response`
        # objects (e.g. Ollama's) carry `"error": null` on success.
        if (err = data["error"]?) && !err.raw.nil?
          STDERR.puts "~~~ #{data}" if TRACE
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
