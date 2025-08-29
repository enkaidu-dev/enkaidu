require "http"

require "./chat_message"
require "./converters"
require "../chat"
require "../function_call"

module LLM::OpenAI
  private class Chat < LLM::Chat
    include Converters

    @conn : ChatConnection

    def initialize(@conn)
      super()
      @messages = [] of Message
      @model = @conn.model
    end

    def with_model(model : String)
      super
      @conn.model = model
    end

    private def call_tool(tool : LLM::Function, tool_call : JSON::Any)
      id = tool_call.dig("id").as_s
      args = if args_str = tool_call.dig("function", "arguments").as_s?
               JSON.parse(args_str)
             else
               JSON::Any.new(nil)
             end
      reply = tool.run(args)
      Message::ToolCall.new tool_call_id: id, name: tool.name, content: reply
    end

    def call_tools_and_ask(tool_calls : Array(JSON::Any), & : LLM::ChatEvent ->)
      calls = 0
      tool_calls.each do |call|
        name = call.dig("function", "name").as_s
        if tool = find_tool? name
          @messages << call_tool tool, call
          calls += 1
        else
          yield unknown_tool_call(call)
        end
      end

      return unless calls.positive?

      ask_post do |msg|
        yield msg
      end
    end

    private def unknown_tool_call(tool_call : JSON::Any)
      {type: "error/unknown", content: tool_call}
    end

    def ask(content : String, attach : Inclusions? = nil, & : LLM::ChatEvent ->)
      @messages << Message::MultiContent.new(prompt: content, attach: attach)

      ask_post do |msg|
        yield msg
      end
    end

    private def ask_post(& : LLM::ChatEvent ->)
      body = to_body

      yield({type: "debug/request", content: JSON.parse(body)}) if debug?

      STDERR.puts ">>> #{body}" if TRACE
      @conn.post_and_stream(body) do |resp|
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
      @messages << aggr_msg
    end

    private def handle_app_json(resp, &)
      # Read the entire body and parse as JSON to determine what to do
      data = JSON.parse(resp.body_io.gets_to_end)
      if data["error"]?
        STDERR.puts "~~~ #{data}" if TRACE
        yield({type: "error/server", content: data})
      else
        process_data(data) do |msg|
          yield msg
        end
        @messages << prepare_message_from(data)
      end
    end

    private def unexpected_response(resp)
      {type: "error/unexpected", content: JSON::Any.new(Hash{
        "headers" => JSON.parse(resp.headers.to_json),
        "body"    => JSON::Any.new(resp.body_io.gets_to_end),
      })}
    end

    private def prepare_message_from(data : JSON::Any)
      m = data.dig("choices", 0, "message").as_h
      # This seems wasteful to emit JSON string only to parse it back
      # But to get the `message` out we need to parse the data,
      # as long as I don't want to transform the JSON::Any tree into
      # a `Message` ... this is good enough.
      Message.from_json(m.to_json)
    end

    private def extract_tool_call_from_message(msg)
      # AWFUL?
      # This FunctionCall object is used to aggregate the
      # tool call when streaming, after which it is
      # retrograded back to its JSON::Any representation
      # as if it had been parsed from a whole incoming
      # tool call.
      tool_call = msg["content"]
      LLM::FunctionCall.new(
        name: tool_call.dig("function", "name").as_s,
        id: tool_call["id"].as_s,
        args_json: tool_call.dig("function", "arguments").as_s
      )
    end

    private def merge_with_recent_tool_call(msg, recent_tool_call)
      tool_call = msg["content"]
      return unless args = tool_call.dig?("function", "arguments")
      recent_tool_call.append_args_json(args.as_s)
    end

    private def wrap_up_tool_call(recent_tool_call, tool_calls)
      # close up recent tool call
      call = jsonify_function_call(recent_tool_call)
      tool_calls << call
      {type: "tool_call", content: call}
    end

    # ameba:disable Metrics/CyclomaticComplexity: It's too messy if I split this up more.
    private def prepare_message_from_streamed_data(stream_io, &)
      tool_calls = [] of JSON::Any
      content = String.build do |text_io|
        recent_tool_call = nil
        stream_io.each_line do |line|
          next if line.empty?

          if line.ends_with? "[DONE]"
            yield({type: "done", content: JSON::Any.new(nil)})
          else
            STDERR.puts "*** #{line}" if TRACE
            data = JSON.parse(line.lchop("data: "))
            process_data(data, from_stream: true) do |msg|
              # gather up the stream chunks
              case msg["type"]
              when "text"
                text_io << msg["content"]
                yield msg
              when "tool_call"
                yield(wrap_up_tool_call(recent_tool_call, tool_calls)) if recent_tool_call
                # and start a new one
                recent_tool_call = extract_tool_call_from_message(msg)
              when "tool_call_merge"
                merge_with_recent_tool_call(msg, recent_tool_call) if recent_tool_call
              when "finish_reason"
                if recent_tool_call
                  yield wrap_up_tool_call(recent_tool_call, tool_calls)
                  recent_tool_call = nil
                end
              else
                yield msg
              end
            end
          end
        end
      end
      Message::Response.new(content: content, tool_calls: tool_calls)
    end

    private def jsonify_function_call(f : LLM::FunctionCall)
      f.append_args_json(nil, complete: true)
      JSON.parse(JSON.build do |json|
        function_call_to_json(f, json)
      end)
    end

    private def process_data(data : JSON::Any, from_stream = false, &)
      yield({type: "debug/data", content: data}) if debug?

      selector = from_stream ? "delta" : "message"

      # check for text content
      content = data.dig?("choices", 0, selector, "content")
      if content && content.raw && content.raw != "" # in case property exists with null value
        yield({type: "text", content: content})
      end

      # check for tool calling
      if tool_calls = data.dig?("choices", 0, selector, "tool_calls")
        tool_calls.as_a.each do |call|
          if call.dig?("function", "name") # in case function block is a dud
            yield({type: "tool_call", content: call})
          else
            # chunks to merge with last tool_call with name
            yield({type: "tool_call_merge", content: call})
          end
        end
      end

      # check if we have a finish reason
      return unless fini = data.dig?("choices", 0, "finish_reason")
      return if fini.raw.nil?
      yield({type: "finish_reason", content: fini})
    end

    private def to_body
      JSON.build do |json|
        chat_to_json(json, model, system_message,
          stream: streaming?,
          messages: @messages,
          tools: each_tool)
      end
    end
  end
end
