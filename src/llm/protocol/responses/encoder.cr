require "json"

require "../../message/message"
require "../../content/content"
require "../../function"
require "../../response_schema"
require "./function_call_builder"

module LLM::Protocol::Responses
  # Encodes the canonical model (`Message`/`Content`/`Function`/`ResponseSchema`)
  # into the OpenAI Responses request body. The wire shape is owned entirely by
  # this protocol encoder, so the canonical `Message` carries no bridge to it.
  private module Encoder
    protected def responses_to_json(json : JSON::Builder, model,
                                    system_message, stream,
                                    session, tools,
                                    reasoning,
                                    reasoning_effort : String? = (reasoning.default? ? nil : reasoning.to_s.downcase),
                                    temperature : Float32? = nil,
                                    response_schema : LLM::ResponseSchema? = nil) : Nil
      json.object do
        json.field "model", model if model

        # Stateless, do not store session on server
        json.field "store", false

        # The system prompt is a top-level field, not a `messages[]` entry.
        json.field "instructions", system_message if system_message
        json.field "stream", stream

        # Configure reasoning behavior based on the Reasoning enum.
        case reasoning
        when LLM::Reasoning::None
          json.field "reasoning" do
            json.object do
              json.field "effort", reasoning_effort || "none"
            end
          end
        else
          json.field "reasoning" do
            json.object do
              json.field "effort", reasoning_effort if reasoning_effort
              json.field "summary", "auto"
            end
          end
          json.field "include" do
            json.array do
              json.string "reasoning.encrypted_content"
            end
          end
        end

        unless temperature.nil?
          json.field "temperature", temperature
        end

        # Structured output on Responses is `text:{format:{... json_schema}}`.
        if response_schema
          json.field "text" do
            json.object do
              json.field "format" do
                json.object do
                  json.field "type", "json_schema"
                  json.field "name", response_schema.name
                  json.field "strict", response_schema.strict?
                  json.field "schema", response_schema.schema
                end
              end
            end
          end
        end

        # The conversation is a flat array of input items; a single canonical
        # `Message` may expand into several items (e.g. an assistant turn with
        # text, reasoning, and tool calls).
        json.field "input" do
          json.array do
            session.each_message(reverse: false) do |msg|
              encode_input_items(msg, json)
            end
          end
        end

        json.field "tool_choice", "auto"
        json.field "tools" do
          json.array do
            tools.each do |tool|
              responses_function_to_json(tool, json)
            end
          end
        end
      end
    end

    # Append the input item(s) for one canonical `Message` to the given
    # `input` array.
    private def encode_input_items(message : LLM::Message, json : JSON::Builder) : Nil
      case message
      when LLM::Message::MultiContent
        # A user message: `{type:"message", role:"user", content:[...]}`.
        json.object do
          json.field "type", "message"
          json.field "role", "user"
          json.field "content" do
            json.array do
              message.content.each { |item| encode_input_content(item, json) }
            end
          end
        end
      when LLM::Message::Response
        encode_response_input_items(message, json)
      when LLM::Message::ToolCall
        # A tool result is a `function_call_output` item; the `name` is dropped
        # on the wire since the `call_id` already links it to its request.
        json.object do
          json.field "type", "function_call_output"
          json.field "call_id", message.tool_call_id
          json.field "output", message.content
        end
      end
    end

    private def encode_response_input_items(message : LLM::Message::Response, json : JSON::Builder) : Nil
      if output = message.responses_output
        output.each do |item|
          encode_responses_output_item(item, message.include_reasoning?, json)
        end
        return
      end

      # Legacy or cross-protocol response: reconstruct from canonical fields.
      # Encrypted reasoning must also be replayed when no summary was returned.
      thoughts = message.reasoning.try(&.presence)
      encrypted = message.encrypted_content.try(&.presence)
      if message.include_reasoning? && (thoughts || encrypted)
        json.object do
          json.field "type", "reasoning"
          json.field "id", message.reasoning_id if message.reasoning_id
          json.field "encrypted_content", message.encrypted_content if message.encrypted_content
          json.field "summary" do
            json.array do
              if thoughts
                json.object do
                  json.field "type", "summary_text"
                  json.field "text", thoughts
                end
              end
            end
          end
        end
      end

      if text = message.content
        unless text.blank?
          json.object do
            json.field "role", "assistant"
            json.field "content", text
          end
        end
      end

      # Tool calls are stored in the canonical history in CC-wire form;
      # extract the canonical fields for the flat `function_call` items.
      if calls = message.tool_calls
        calls.each do |call|
          json.object do
            json.field "type", "function_call"
            json.field "call_id", call.dig("id").as_s
            json.field "name", call.dig("function", "name").as_s
            json.field "arguments", call.dig("function", "arguments").as_s? || ""
          end
        end
      end
    end

    # Convert one output item to its input form without disturbing the captured
    # order. Output-only identifiers and status fields are intentionally omitted.
    private def encode_responses_output_item(item : JSON::Any, include_reasoning : Bool, json : JSON::Builder) : Nil
      case item["type"]?.try(&.as_s?)
      when "message"
        encode_responses_message(item, json)
      when "reasoning"
        encode_responses_reasoning(item, include_reasoning, json)
      when "function_call"
        encode_responses_function_call(item, json)
      else
        raise ArgumentError.new("Cannot replay unsupported Responses output item type: #{item["type"]?.try(&.as_s?) || "missing"}")
      end
    end

    private def encode_responses_message(item : JSON::Any, json : JSON::Builder) : Nil
      parts = item["content"]?.try(&.as_a?)
      return unless parts
      json.object do
        json.field "role", "assistant"
        json.field "content" do
          json.array do
            parts.each { |part| encode_responses_message_part(part, json) }
          end
        end
      end
    end

    private def encode_responses_message_part(part : JSON::Any, json : JSON::Builder) : Nil
      part_type = part["type"]?.try(&.as_s?)
      return unless part_type == "output_text" || part_type == "refusal"
      json.object do
        json.field "type", part_type
        json.field "text", part["text"]? if part["text"]?
        json.field "refusal", part["refusal"]? if part["refusal"]?
      end
    end

    private def encode_responses_reasoning(item : JSON::Any, include_reasoning : Bool, json : JSON::Builder) : Nil
      return unless include_reasoning
      json.object do
        json.field "type", "reasoning"
        json.field "id", item["id"]? if item["id"]?
        json.field "encrypted_content", item["encrypted_content"]? if item["encrypted_content"]?
        json.field "summary" do
          json.array do
            if summary = item["summary"]?.try(&.as_a?)
              summary.each do |part|
                json.object do
                  json.field "type", (part["type"]? || JSON::Any.new("summary_text"))
                  json.field "text", part["text"]? if part["text"]?
                end
              end
            end
          end
        end
      end
    end

    private def encode_responses_function_call(item : JSON::Any, json : JSON::Builder) : Nil
      json.object do
        json.field "type", "function_call"
        json.field "call_id", (item["call_id"]? || item["id"]?)
        json.field "name", (item["name"]? || JSON::Any.new(""))
        json.field "arguments", (item["arguments"]? || JSON::Any.new(""))
      end
    end

    # Map a canonical `Content` part onto a Responses input part.
    private def encode_input_content(item, json : JSON::Builder) : Nil
      case item
      when LLM::Content::Text
        json.object do
          json.field "type", "input_text"
          json.field "text", item.text
        end
      when LLM::Content::ImageUrl
        json.object do
          json.field "type", "input_image"
          json.field "image_url", item.image_url["url"]
        end
      when LLM::Content::FileData
        json.object do
          json.field "type", "input_file"
          json.field "file_data", item.file["file_data"]
          json.field "filename", item.file["filename"]
        end
      when LLM::Content::InputAudio
        json.object do
          json.field "type", "input_audio"
          json.field "input_audio" do
            json.object do
              json.field "data", item.input_audio["data"]
              json.field "format", item.input_audio["format"]
            end
          end
        end
      end
    end

    # A tool definition is flat on the Responses wire:
    # `{type:"function", name, description, parameters}` (no nested `function`).
    protected def responses_function_to_json(f : LLM::Function, json : JSON::Builder)
      json.object do
        json.field "type", "function"
        json.field "name", f.name
        json.field "description", f.description
        json.field "parameters" do
          f.input_json_schema(json)
        end
      end
    end
  end
end
