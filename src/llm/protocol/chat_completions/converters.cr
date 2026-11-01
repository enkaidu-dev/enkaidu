require "json"

require "../../message/message"
require "./function_call_builder"
require "../../function"
require "../../response_schema"

module LLM::Protocol::ChatCompletions
  private module Converters
    protected def function_call_to_json(f : FunctionCallBuilder, json : JSON::Builder)
      json.object do
        json.field "type", "function"
        json.field "id", f.id
        json.field "function" do
          json.object do
            json.field "arguments", f.args_json
            json.field "name", f.name
          end
        end
        if extra = f.extra_content
          json.field "extra_content", extra
        end
      end
    end

    protected def function_to_json(f : LLM::Function, json : JSON::Builder)
      json.object do
        json.field "type", "function"
        json.field "function" do
          json.object do
            json.field "name", f.name
            json.field "description", f.description
            json.field "parameters" do
              f.input_json_schema(json)
            end
            # json.field "additionalProperties", false
          end
        end
      end
    end

    private def chat_to_json(json : JSON::Builder, model,
                             system_message, stream, session, tools,
                             reasoning : Reasoning, temperature : Float32? = nil, response_schema : ResponseSchema? = nil)
      json.object do
        json.field "model", model if model
        json.field "stream", stream
        if stream
          # Ask for usage when streaming
          json.field "stream_options" do
            json.object do
              json.field "include_usage", true
            end
          end
        end
        unless reasoning.default?
          json.field "reasoning_effort", reasoning.to_s.downcase
        end
        unless temperature.nil?
          json.field "temperature", temperature
        end
        if response_schema
          json.field "response_format" do
            json.object do
              json.field "type", "json_schema"
              json.field "json_schema", response_schema
            end
          end
        end
        json.field "messages" do
          json.array do
            if sm = system_message
              json.object do
                json.field "role", "system"
                json.field "content", sm
              end
            end
            session.each_message(reverse: false) do |msg|
              encode_message(msg, json)
            end
          end
        end
        json.field "tool_choice", "auto"
        json.field "tools" do
          json.array do
            tools.each do |tool|
              function_to_json(tool, json)
            end
          end
        end
      end
    end

    # Encode one canonical Message as a Chat-Completions wire entry. The wire
    # shape is owned by this protocol encoder (not by the canonical model), so
    # `Message` no longer carries a `to_protocol_json` bridge. Field order and
    # conditionals mirror the old bridge exactly:
    #   - MultiContent: role, content[]
    #   - ToolCall:     role, tool_call_id, name, content
    #   - Response:     role, reasoning (only when present AND include_reasoning?),
    #                   content, tool_calls (only when non-empty)
    private def encode_message(message : Message, json : JSON::Builder)
      json.object do
        case message
        when Message::MultiContent
          json.field "role", message.role
          json.field "content" do
            json.array do
              message.content.each do |item|
                item.to_json(json)
              end
            end
          end
        when Message::ToolCall
          json.field "role", message.role
          json.field "tool_call_id", message.tool_call_id
          json.field "name", message.name
          json.field "content", message.content
        when Message::Response
          json.field "role", message.role
          if thoughts = message.reasoning
            json.field "reasoning", thoughts if thoughts.presence && message.include_reasoning?
          end
          json.field "content", message.content
          if calls = message.tool_calls
            json.field "tool_calls", calls unless calls.empty?
          end
        end
      end
    end

    protected def function_to_s(f : LLM::Function.class, io : IO)
      JSON.build(io) do |json|
        function_to_json(f, json)
      end
    end
  end
end
