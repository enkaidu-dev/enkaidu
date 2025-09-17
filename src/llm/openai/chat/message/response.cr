require "../message"
require "../usage"

module LLM::OpenAI
  # Represents a response message from the LLM
  class Message::Response < Message
    include JSON::Serializable

    property content : String?

    @[JSON::Field(ignore_serialize: ((toolcalls = @tool_calls).nil? || toolcalls.empty?))]
    property tool_calls : Array(JSON::Any)?

    # Sidecar to response message so we can keep the usage together with it.
    # Not serialized.
    @[JSON::Field(ignore: true)]
    property usage : Usage? = nil

    def initialize(@content, @tool_calls = nil)
      @role = "assistant"
    end
  end
end
