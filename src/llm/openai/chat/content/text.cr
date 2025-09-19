require "../content"

module LLM::OpenAI
  # Represents text `content` within a message to the LLM
  class Content::Text < Content
    property text : String

    def initialize(@text)
      @type = "text"
    end

    # Emit this content as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      yield({type: "query/text", content: JSON::Any.new(text)})
    end
  end
end
