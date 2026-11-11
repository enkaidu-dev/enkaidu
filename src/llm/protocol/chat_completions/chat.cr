require "http"

require "../../chat"
require "../../message/message"
require "../../history"

require "./encoder"
require "./function_call_builder"

module LLM::Protocol::ChatCompletions
  class Chat < LLM::Chat
    include Encoder

    @conn : Connection

    def initialize(@conn)
      super()
      @model = @conn.model
    end

    def with_model(model : String)
      super
      @conn.model = model
    end

    # The one protocol contract: encode the current session, POST it (SSE or JSON),
    # yield canonical `ChatEvent`s, and append the resulting `Message::Response` to
    # history. Session management and the tool loop live on the base `LLM::Chat`.
    def post_session(response_schema : ResponseSchema? = nil,
                     exclude_reasoning_in_history = false,
                     exclude_reasoning_skip = 0,
                     & : LLM::ChatEvent ->) : Nil
      @history.exclude_past_reasoning(skip_turns: exclude_reasoning_skip) if exclude_reasoning_in_history
      body = to_body(response_schema)

      yield({type: LLM::Event::DebugRequest, content: JSON.parse(body)}) if debug?

      STDERR.puts ">>> #{body}" if TRACE
      @conn.post_and_stream(body, session_id) do |resp|
        STDERR.puts "<<< #{resp.headers}" if TRACE
        if resp.status.too_many_requests?
          yield warn_too_many_requests_delay(JSON::Any.new("#{resp.status_code} #{resp.status_message}"))
          raise TooManyRequests.new(@conn.path)
        end

        case resp.content_type
        when "text/event-stream" then handle_text_event_stream(resp) { |msg| yield msg }
        when "application/json"  then handle_app_json(resp) { |msg| yield msg }
        else
          # we don't know what to do if it's not SSE or JSON
          yield unexpected_response(resp)
        end
      end
    end

    private def handle_text_event_stream(resp, &)
      # Yield each line from the stream, skipping blank lines
      stream_io = resp.body_io
      aggr_msg = prepare_message_from_streamed_data(stream_io) do |msg|
        yield msg
      end
      STDERR.puts "+++ #{aggr_msg.to_json}" if TRACE
      append_message aggr_msg
    end

    private def handle_app_json(resp, &) : Nil
      # Read the entire body and parse as JSON to determine what to do
      body = resp.body_io.gets_to_end
      begin
        data = JSON.parse(body)
        raise_if_rate_limited(data) { |msg| yield msg }
        if (err = data["error"]?) && !err.raw.nil?
          STDERR.puts "~~~ #{data}" if TRACE
          yield({type: LLM::Event::ErrorServer, content: data})
        else
          content = nil.as(String?)
          reasoning = nil.as(String?)
          refusal = data.dig?("choices", 0, "message", "refusal").try(&.as_s?)
          usage = nil.as(Usage?)
          process_data(data) do |msg|
            case msg["type"]
            when LLM::Event::Text
              content = content.to_s + (msg["content"].as_s? || "")
            when LLM::Event::ReasoningEvent
              reasoning = msg["content"].to_s
            when LLM::Event::Usage
              usage = Usage.from_json(msg["content"].to_json)
            end
            yield msg
          end
          # The CC-wire tool calls (for history / next request encoding) are
          # kept separate from the canonical events yielded to the app.
          tool_calls = if tc = data.dig?("choices", 0, "message", "tool_calls")
                         tc.as_a
                       end
          msg = Message::Response.new(
            content: content, reasoning: reasoning, tool_calls: tool_calls)
          msg.refusal = !refusal.nil?
          msg.usage = usage if usage
          append_message(msg)
        end
      rescue ex : JSON::ParseException
        LLM.show_error_trace(ex, data_label: "body", data: body)
      end
    end

    private def raise_if_rate_limited(data : JSON::Any, &) : Nil
      # Azure AI can report rate control inside a successful HTTP response.
      if data.dig?("error", "type").try(&.as_s?.try(&.starts_with?("too_many_request")))
        yield warn_too_many_requests_delay(data)
        raise TooManyRequests.new(data.to_s)
      end
    end

    private def unexpected_response(resp)
      {type: LLM::Event::ErrorUnexpected, content: JSON::Any.new(Hash{
        "headers" => JSON.parse(resp.headers.to_h.to_json),
        "body"    => JSON::Any.new(resp.body_io.gets_to_end),
      })}
    end

    private def prepare_message_from(data : JSON::Any)
      m = data.dig("choices", 0, "message").as_h
      # This seems wasteful to emit JSON string only to parse it back
      # But to get the `message` out we need to parse the data,
      # as long as I don't want to transform the JSON::Any tree into
      # a `Message` ... this is good enough.
      msg = Message.from_json(m.to_json)
      if msg.is_a? Message::Response
        if usg = data["usage"]?
          msg.usage = Usage.from_json(usg.to_json)
        end
      end
      msg
    end

    private def extract_tool_call_from_message(msg) : FunctionCallBuilder
      # This FunctionCallBuilder object is used to aggregate the
      # tool call when streaming; a canonical LLM::FunctionCall is
      # built from it when complete (in wrap_up_tool_call).
      tool_call = msg["content"]
      FunctionCallBuilder.new(
        name: tool_call.dig("function", "name").as_s,
        # Some servers (certain vLLM builds) omit `id` on the first chunk;
        # tolerate with the empty string rather than crashing the line into the
        # per-line rescue (which would silently drop the whole call).
        id: tool_call.dig?("id").try(&.as_s) || "",
        # vLLM doesn't include empty `arguments:`, so if not present fill with empty string to append to.
        args_json: tool_call.dig?("function", "arguments").try(&.as_s) || "",
        extra_content: tool_call.dig?("extra_content")
      )
    end

    private def merge_with_recent_tool_call(msg, recent_tool_call : FunctionCallBuilder) : Nil
      tool_call = msg["content"]
      return unless args = tool_call.dig?("function", "arguments")
      recent_tool_call.append_args_json(args.as_s)
    end

    private def wrap_up_tool_call(recent_tool_call : FunctionCallBuilder, tool_calls)
      # Close up the recent tool call: retain the CC wire form for history /
      # request encoding, but emit the canonical shape as the event content.
      tool_calls << jsonify_function_call(recent_tool_call)
      {
        type:    LLM::Event::ToolCallRequested,
        content: LLM::FunctionCall.new(recent_tool_call.id, recent_tool_call.name, recent_tool_call.args_json).json,
      }
    end

    private def receiving_tool_call(starting_tool_call : FunctionCallBuilder)
      {type: LLM::Event::ReceivingToolCall, content: JSON::Any.new(starting_tool_call.name)}
    end

    # ameba:disable Metrics/CyclomaticComplexity: It's too messy if I split this up more.
    private def prepare_message_from_streamed_data(stream_io, &)
      tool_calls = [] of JSON::Any
      usage = nil
      refusal = false
      content = ""
      reasoning = String.build do |think_io|
        content = String.build do |text_io|
          recent_tool_call = nil
          stream_io.each_line do |line|
            line = line.strip
            next unless line.starts_with?("data:")
            line = line.lchop("data:").lchop(" ")

            if line == "[DONE]"
              yield({type: LLM::Event::Done, content: JSON::Any.new(nil)})
            else
              STDERR.puts "*** #{line}" if TRACE
              data = JSON.parse(line)
              raise_if_rate_limited(data) { |msg| yield msg }
              if refused = data.dig?("choices", 0, "delta", "refusal")
                refusal ||= !refused.raw.nil?
              end
              process_data(data, from_stream: true) do |msg|
                # gather up the stream chunks
                case msg["type"]
                when LLM::Event::Text
                  text_io << msg["content"]
                  yield msg
                when LLM::Event::ReasoningEvent
                  think_io << msg["content"]
                  yield msg
                when LLM::Event::ToolCallRequested
                  yield(wrap_up_tool_call(recent_tool_call, tool_calls)) if recent_tool_call
                  # and start a new one
                  recent_tool_call = extract_tool_call_from_message(msg)
                  yield(receiving_tool_call(recent_tool_call))
                when LLM::Event::ToolCallMerge
                  merge_with_recent_tool_call(msg, recent_tool_call) if recent_tool_call
                when LLM::Event::FinishReason
                  if recent_tool_call
                    yield wrap_up_tool_call(recent_tool_call, tool_calls)
                    recent_tool_call = nil
                  end
                when LLM::Event::Usage
                  usage = Usage.from_json(msg["content"].to_json)
                else
                  yield msg
                end
              end
            end
          rescue ex : JSON::ParseException
            LLM.show_error_trace(ex, data_label: "line", data: line)
          end
          # A stream can end with a tool call still in flight — no trailing
          # finish_reason chunk, or a truncated stream. Finalize it so it is
          # appended to `tool_calls` and emitted as a canonical event. A stream
          # that finished normally has already cleared `recent_tool_call` via the
          # FinishReason case, making this a no-op there.
          yield(wrap_up_tool_call(recent_tool_call, tool_calls)) if recent_tool_call
        end
      end
      msg = Message::Response.new(
        content: content, reasoning: reasoning, tool_calls: tool_calls)
      msg.refusal = refusal
      msg.usage = usage if usage
      msg
    end

    private def jsonify_function_call(f : FunctionCallBuilder)
      f.append_args_json(nil, complete: true)
      JSON.parse(JSON.build do |json|
        function_call_to_json(f, json)
      end)
    end

    private def process_content(content, &) : Nil
      if content && content.raw && content.raw != "" # in case property exists with null value
        yield({type: LLM::Event::Text, content: content})
      end
    end

    private def process_reasoning(text, &) : Nil
      if text && text.raw && text.raw != "" # in case property exists with null value
        yield({type: LLM::Event::ReasoningEvent, content: text})
      end
    end

    private def process_refusal(data_selector, &) : Nil
      if refusal = data_selector["refusal"]?
        process_content(refusal) { |msg| yield msg } unless refusal.raw.nil?
      end
    end

    private def cc_tool_call_to_function_call(call : JSON::Any)
      LLM::FunctionCall.new(
        call.dig("id").as_s,
        call.dig("function", "name").as_s,
        call.dig("function", "arguments").as_s? || "",
      )
    end

    private def process_tool_calls(tool_calls, from_stream : Bool, &) : Nil
      tool_calls.as_a.each do |call|
        if call.dig?("function", "name") # in case function block is a dud
          yield({
            type:    LLM::Event::ToolCallRequested,
            content: from_stream ? call : cc_tool_call_to_function_call(call).json,
          })
        else
          # chunks to merge with last tool_call with name
          yield({type: LLM::Event::ToolCallMerge, content: call})
        end
      end
    end

    private def process_data(data : JSON::Any, from_stream = false, &) : Nil
      yield({type: LLM::Event::DebugData, content: data}) if debug?

      selector = from_stream ? "delta" : "message"

      if data_selector = data.dig?("choices", 0, selector)
        # check for reasoning content first
        # - some models use `reasoning` property
        # - some models use `reasoning_content` property
        if content = data_selector["reasoning"]? ||
                     data_selector["reasoning_content"]? ||
                     data_selector["thinking"]?
          process_reasoning(content) { |msg| yield msg }
        end

        # Refusal text is exposed as canonical text; the caller separately
        # records the protocol-neutral refusal flag on the response.
        process_refusal(data_selector) { |msg| yield msg }

        # check for text content
        content = data_selector["content"]?
        process_content(content) { |msg| yield msg }

        # check for tool calling
        if tool_calls = data_selector["tool_calls"]?
          process_tool_calls(tool_calls, from_stream) { |msg| yield msg }
        end
      end

      # check for usage chunk
      if (usage = data["usage"]?) && usage.raw
        yield({type: LLM::Event::Usage, content: usage})
      end

      # check if we have a finish reason
      return unless fini = data.dig?("choices", 0, "finish_reason")
      return if fini.raw.nil?
      yield({type: LLM::Event::FinishReason, content: fini})
    end

    private def to_body(response_schema : ResponseSchema? = nil)
      JSON.build do |json|
        chat_to_json(json, model, system_message,
          stream: streaming?,
          session: @history,
          tools: each_tool,
          reasoning: reasoning,
          response_schema: response_schema)
      end
    end
  end
end
