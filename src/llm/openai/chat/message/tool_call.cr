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

    # Emit this message as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      body = <<-EMIT
          {
            "function" : {
              "name" : #{name.to_json},
              "content" : #{content.to_json}
            }
          }
          EMIT
      yield({
        type:    "tool_call/done",
        content: JSON.parse(body),
      })
    end
  end
end
