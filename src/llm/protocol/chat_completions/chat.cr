require "http"

require "../../chat"
require "../../content/content"
require "../../message/message"
require "../../history"

require "./converters"
require "./function_call_builder"

module LLM::Protocol::ChatCompletions
  class Chat < LLM::Chat
    include Converters

    @conn : Connection
    @history : History

    # Usage report in most recent response from LLM.
    getter usage : Usage? = nil

    def initialize(@conn)
      super()
      @history = History.new
      @model = @conn.model
      @usage = nil
    end

    def erase_history : Nil
      @history = History.new
      @usage = nil
    end

    def save(io : IO | JSON::Builder) : Nil
      @history.to_json(io)
    end

    def load(io : IO | String) : Nil
      @history = History.from_json(io)
      @usage = @history.last_usage
    end

    def tail(num_responses = 1, & : ChatEvent ->) : Nil
      @history.tail_chats(num_responses) { |chat_ev| yield chat_ev }
    end

    def send_tail(to : Chat, num_responses = 1, filter_by_role : String? = nil) : Nil
      @history.transfer_tail_chats(to: to.@history,
        num: num_responses, filter_by_role: filter_by_role)
    end

    def append_conversations(to : Chat, which : Conversation) : Bool
      case which
      when .latest_full?
        @history.append_last_conversation(to: to.@history)
      when .latest_outer?
        @history.append_last_conversation(to: to.@history, outer: true)
      when .session_full?
        @history.append_session_conversation(to: to.@history)
      when .session_outer?
        @history.append_session_conversation(to: to.@history, outer: true)
      end
      true
    end

    # Extract last response from `assistant` and yield it to caller to
    # process and return a named tuple with a `prompt` and `response` to return
    # as a message array that caller can inject into a session. Returns `nil` if
    # no response in the current history.
    def append_last_response_as_prompt(to : Chat, prompt_prefix : String, new_response : String) : Bool
      @history.append_transformed_last_response?(to: to.@history) do |content|
        {
          response: new_response,
          prompt:   String.build { |str| str << prompt_prefix << content },
        }
      end
    end

    # Extract conversations and return as a JSON string
    def extract_conversations(which : Conversation) : String?
      extract = case which
                when .latest_full?
                  @history.extract_last_conversation
                when .latest_outer?
                  @history.extract_last_conversation(outer: true)
                when .session_full?
                  @history.extract_session_conversation
                when .session_outer?
                  @history.extract_session_conversation(outer: true)
                end
      extract.try(&.to_json)
    end

    # Replace current session with a "fork" of the session from the given
    # `Chat` instance; may fail if `self` is not compatible.
    # Optionally, exclude the last "turn" (last user prompt and subsequent responses).
    def fork(from : Chat, exclude_last_turn = false) : Nil
      @history.branch(from.@history, exclude_last_turn)
      @usage = @history.last_usage
    end

    def append_message(msg)
      usage = nil
      if msg.is_a? Message::Response
        @usage = usage = msg.usage
      end
      @history.append_message msg, usage
    end

    def with_model(model : String)
      super
      @conn.model = model
    end

    private def error_calling_tool(call_id, tool_name, error, instruction = nil.as(String?))
      Message::ToolCall.new(
        tool_call_id: call_id,
        name: tool_name,
        content: (instruction ? {error: error, instruction: instruction} : {error: error}).to_json)
    end

    private def call_tool(tool : LLM::Function,
                          tool_call : LLM::FunctionCall,
                          attachments : Message::MultiContent?)
      args = if tool_call.arguments.blank?
               JSON::Any.new(nil)
             else
               JSON.parse(tool_call.arguments)
             end
      reply = tool.run(args)
      # Detect attachments and start gathering up to send after the tool call
      # responses. We need to do this to make sure we conform to the message ordering
      # enforced by many model servers.
      if reply.has_attachments?
        if attachments.nil?
          attachments = Message::MultiContent.new("Additional content related to prior tool calls.")
        end
        reply.each_attachment do |att|
          case att
          when Function::Reply::Text  then attachments.text(att.data)
          when Function::Reply::File  then attachments.file_data(att.base64_data, att.file_name)
          when Function::Reply::Image then attachments.image_url(att.image_url.to_s)
          when Function::Reply::Audio then attachments.input_audio(att.base64_data, att.format)
          end
        end
      end
      {
        tool_call_response: Message::ToolCall.new(tool_call_id: tool_call.id, name: tool.name, content: reply.content),
        attachments:        attachments,
      }
    end

    # Invoke tool calls and return number of calls made; if positive call `re_ask` to
    # hand call results to the models to process
    def call_tools_and_setup_ask(tool_calls : Array(LLM::FunctionCall), & : LLM::ChatEvent ->) : Int32
      attachments = nil.as(Message::MultiContent?)
      calls = 0
      tool_calls.each do |call|
        if tool = find_tool?(call.name)
          yield({type: LLM::Event::CallingTool, content: call.json})
          result = call_tool(tool, call, attachments)
          append_message(result[:tool_call_response])
          attachments = result[:attachments]
        else
          yield unknown_tool_call(call)
          append_message error_calling_tool(
            call.id,
            call.name,
            error: case call.name
            when .blank? then "The tool name cannot be empty string."
            else              "The tool #{call.name} is not installed. Consider installing it first."
            end
          )
        end
        calls += 1
      end
      unless attachments.nil?
        # Append the attachments after all the tool call responses
        append_message(attachments)
      end
      calls
    end

    private def unknown_tool_call(tool_call : LLM::FunctionCall)
      {type: LLM::Event::ErrorUnknownToolCall, content: tool_call.json}
    end

    def import(prompt : MCP::PromptResult, emit = false, & : ChatEvent ->) : Nil
      @history.import(prompt, emit) { |event| yield event }
    end

    def re_ask(response_schema : ResponseSchema? = nil,
               exclude_reasoning_in_history = false,
               exclude_reasoning_skip = 0,
               & : ChatEvent ->) : Nil
      ask_post(response_schema, exclude_reasoning_in_history, exclude_reasoning_skip) do |msg|
        yield msg
      end
    end

    def squish
      @history = @history.squish_turns
      @usage = nil
    end

    def ask(content : String,
            attach : ChatInclusions? = nil,
            response_schema : ResponseSchema? = nil,
            exclude_reasoning_in_history = false,
            exclude_reasoning_skip = 0,
            & : ChatEvent ->) : Nil
      append_message Message::MultiContent.new(prompt: content, attach: attach)

      ask_post(response_schema, exclude_reasoning_in_history, exclude_reasoning_skip) do |msg|
        yield msg
      end
    end

    private def ask_post(response_schema : ResponseSchema? = nil,
                         exclude_reasoning_in_history = false,
                         exclude_reasoning_skip = 0,
                         & : LLM::ChatEvent ->) : Nil
      @history.exclude_past_reasoning(skip_turns: exclude_reasoning_skip) if exclude_reasoning_in_history
      body = to_body(response_schema)

      yield({type: LLM::Event::DebugRequest, content: JSON.parse(body)}) if debug?

      STDERR.puts ">>> #{body}" if TRACE
      @conn.post_and_stream(body, session_id) do |resp|
        STDERR.puts "<<< #{resp.headers}" if TRACE
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
        if data["error"]?
          STDERR.puts "~~~ #{data}" if TRACE
          yield({type: LLM::Event::ErrorServer, content: data})
        else
          content = nil
          reasoning = nil
          usage = nil
          process_data(data) do |msg|
            case msg["type"]
            when LLM::Event::Text
              content = msg["content"].to_s
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
          msg.usage = usage if usage
          append_message(msg)
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
      content = ""
      reasoning = String.build do |think_io|
        content = String.build do |text_io|
          recent_tool_call = nil
          stream_io.each_line do |line|
            line = line.strip
            next if line.empty?

            if line.ends_with? "[DONE]"
              yield({type: LLM::Event::Done, content: JSON::Any.new(nil)})
            else
              STDERR.puts "*** #{line}" if TRACE
              data = JSON.parse(line.lchop("data: "))
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
          rescue ex
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
