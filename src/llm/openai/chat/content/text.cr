require "../content"

module LLM::OpenAI
  # Represents text `content` within a message to the LLM
  class Content::Text < Content
    property text : String

    def initialize(@text)
      @type = "text"
    end
  end
end
