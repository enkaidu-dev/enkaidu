require "./event"

module Enkaidu::WUI::Render
  class LLMToolCall < Event
    getter name : String
    getter args : String

    def initialize(@name, @args)
      super("llm_tool_call")
    end
  end

  class LLMTextFragment < Event
    getter fragment : String
    getter? reasoning : Bool

    def initialize(@fragment, @reasoning)
      super("llm_text_fragment")
    end
  end

  class LLMText < Event
    getter content : String
    getter? reasoning : Bool

    def initialize(@content, @reasoning)
      super("llm_text")
    end
  end

  class LLMImageUrl < Event
    getter url : String

    def initialize(@url)
      super("llm_image_url")
    end
  end
end
