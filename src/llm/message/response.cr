require "./message"
require "../usage"

module LLM
  # Represents a response message from the LLM
  class Message::Response < Message
    ROLE = "assistant"

    property content : String?

    @[JSON::Field(ignore_serialize: ((reasoning = @reasoning).nil? || reasoning.empty?))]
    property reasoning : String?

    # Optional metadata for Responses protocol stateless reasoning continuity
    property reasoning_id : String? = nil
    property encrypted_content : String? = nil

    # Ordered Responses output items, retained for lossless stateless replay.
    # Nil means the response came from another protocol or a legacy session.
    property responses_output : Array(JSON::Any)? = nil

    # If `false` don't include reasoning when resending this message to the model
    property? include_reasoning = true

    @[JSON::Field(ignore_serialize: ((toolcalls = @tool_calls).nil? || toolcalls.empty?))]
    property tool_calls : Array(JSON::Any)?

    # Sidecar to response message so we can keep the usage together with it.
    # Not serialized. Keeping this here as a convenience when parsing for now.
    # Ideally it would better if it was only in the `MessagePlus` wrapper.
    @[JSON::Field(ignore: true)]
    property usage : Usage? = nil

    def initialize(@content, @reasoning, @tool_calls = nil, @reasoning_id : String? = nil, @encrypted_content : String? = nil)
      @role = "assistant"
    end

    # Emit this message as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      if text = reasoning
        yield({type: LLM::Event::ReasoningEvent, content: JSON::Any.new(text)})
      end
      if text = content
        yield({type: LLM::Event::Text, content: JSON::Any.new(text)})
      end
      tool_calls.try &.each do |call|
        # `call` is the CC-wire tool call {id, function:{name, arguments}, …};
        # emit it in the canonical shape (the wire form is only for history).
        yield({
          type:    LLM::Event::ToolCallRequested,
          content: LLM::FunctionCall.new(
            call.dig("id").as_s,
            call.dig("function", "name").as_s,
            call.dig("function", "arguments").as_s? || "",
          ).json,
        })
      end
    end

    # Return a copy with just the content.
    protected def dup_without_tool_calls
      copy = self.class.new(content, reasoning, reasoning_id: reasoning_id, encrypted_content: encrypted_content)
      copy.responses_output = responses_output.try(&.reject { |item| item["type"]?.try(&.as_s?) == "function_call" })
      copy
    end
  end
end
