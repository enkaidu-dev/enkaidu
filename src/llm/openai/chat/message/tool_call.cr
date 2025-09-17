require "../message"

module LLM::OpenAI
  # Represents a tool-call result message in a request to the LLM
  class Message::ToolCall < Message
    property tool_call_id : String
    property name : String
    property content : String

    def initialize(@tool_call_id, @name, @content)
      @role = "tool"
    end
  end
end
