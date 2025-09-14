require "json"

require "../function"
require "../function_call"

module LLM::OpenAI
  private module Converters
    protected def param_to_json(p : LLM::Param, json : JSON::Builder)
      json.field p.name do
        json.object do
          json.field "type", p.type.json_type
          json.field "description", p.description
        end
      end
    end

    protected def function_call_to_json(f : LLM::FunctionCall, json : JSON::Builder)
      json.object do
        json.field "type", "function"
        json.field "id", f.id
        json.field "function" do
          json.object do
            json.field "arguments", f.args_json
            json.field "name", f.name
          end
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

    private def chat_to_json(json : JSON::Builder, model, system_message, stream, messages, tools)
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
        json.field "messages" do
          json.array do
            if sm = system_message
              json.object do
                json.field "role", "system"
                json.field "content", sm
              end
            end
            messages.each do |msg|
              msg.to_json(json)
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

    protected def function_to_s(f : LLM::Function.class, io : IO)
      JSON.build(io) do |json|
        function_to_json(f, json)
      end
    end
  end
end
