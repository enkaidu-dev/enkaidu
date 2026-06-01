require "../message"
require "../usage"

module LLM::OpenAI
  # Represents a response message from the LLM
  class Message::Response < Message
    property content : String?

    @[JSON::Field(ignore_serialize: ((reasoning = @reasoning).nil? || reasoning.empty?))]
    property reasoning : String?

    # If `false` don't include reasoning when resending this message to the model
    property? include_reasoning = true

    @[JSON::Field(ignore_serialize: ((toolcalls = @tool_calls).nil? || toolcalls.empty?))]
    property tool_calls : Array(JSON::Any)?

    # Sidecar to response message so we can keep the usage together with it.
    # Not serialized. Keeping this here as a convenience when parsing for now.
    # Ideally it would better if it was only in the `MessagePlus` wrapper.
    @[JSON::Field(ignore: true)]
    property usage : Usage? = nil

    def initialize(@content, @reasoning, @tool_calls = nil)
      @role = "assistant"
    end

    # Emit this message as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      if text = reasoning
        yield({type: "reasoning", content: JSON::Any.new(text)})
      end
      if text = content
        yield({type: "text", content: JSON::Any.new(text)})
      end
      tool_calls.try &.each do |call|
        yield({
          type:    "tool_call_requested",
          content: call,
        })
      end
    end

    protected def protocol_fields_to_json(json : JSON::Builder)
      super
      if thoughts = @reasoning
        if thoughts.presence && include_reasoning?
          json.field "reasoning", thoughts
        end
      end
      json.field "content", content
      if (calls = @tool_calls) && !calls.empty?
        json.field "tool_calls", calls
      end
    end
  end
end
