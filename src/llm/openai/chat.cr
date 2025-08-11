require "http"
require "json"

require "./converters"
require "../chat"
require "../function_call"

module LLM::OpenAI
  alias MessageValue = String | JSON::Any | Array(JSON::Any)
  alias Message = Hash(Symbol, MessageValue)

  private class Chat < LLM::Chat
    include Converters

    @conn : ChatConnection

    def initialize(@conn)
      super()
      @messages = [] of Message
    end

    private def call_tool(tool : LLM::Function, tool_call : JSON::Any)
      id = tool_call.dig("id").as_s
      args = if args_str = tool_call.dig("function", "arguments").as_s?
               JSON.parse(args_str)
             else
               JSON::Any.new(nil)
             end
      reply = tool.run(args)
      Message{
        :role         => "tool",
        :tool_call_id => id,
        :name         => tool.name,
        :content      => reply,
      }
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

    def ask(content : String, & : LLM::ChatEvent ->)
      @messages << Message{
        :role    => "user",
        :content => content,
      }
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

    private def message_key_to_sym(k : String)
      case k
      when "role"       then :role
      when "content"    then :content
      when "tool_calls" then :tool_calls
      else                   nil
      end
    end

    private def prepare_message_from(data)
      msg = Message.new
      m = data.dig("choices", 0, "message").as_h
      m.each do |k, v|
        if v
          sym = message_key_to_sym(k)
          msg[sym] = v if sym
        end
      end
      msg
    end

    private def prepare_message_from_streamed_data(stream_io, &)
      message = Message.new
      tool_calls = [] of JSON::Any
      recent_tool_call = nil
      content = String.build do |text_io|
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
                if recent_tool_call
                  call = jsonify_function_call(recent_tool_call)
                  tool_calls << call
                  yield({type: "tool_call", content: call})
                end
                # AWFUL?
                # This FunctionCall object is used to aggregate the
                # tool call when streaming, after which it is
                # retrograded back to its JSON::Any representation
                # as if it had been parsed from a whole incoming
                # tool call.
                tool_call = msg["content"]
                recent_tool_call = LLM::FunctionCall.new(
                  name: tool_call.dig("function", "name").as_s,
                  id: tool_call["id"].as_s,
                  args_json: tool_call.dig("function", "arguments").as_s
                )
              when "tool_call_merge"
                if recent_tool_call
                  tool_call = msg["content"]
                  if args = tool_call.dig?("function", "arguments")
                    recent_tool_call.append_args_json(args.as_s)
                  end
                end
              when "finish_reason"
                if recent_tool_call
                  call = jsonify_function_call(recent_tool_call)
                  tool_calls << call
                  recent_tool_call = nil
                  yield({type: "tool_call", content: call})
                end
              else
                yield msg
              end
            end
          end
        end
      end
      message[:role] = "assistant"
      message[:content] = content
      message[:tool_calls] = tool_calls unless tool_calls.empty?
      message
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
      if fini = data.dig?("choices", 0, "finish_reason")
        unless fini.raw.nil?
          yield({type: "finish_reason", content: fini})
        end
      end
    end

    private def to_body
      JSON.build do |json|
        chat_to_json(json, model, system_message,
          stream: streaming?,
          messages: @messages,
          tools: @tools.each_value)
      end
    end
  end
end
