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

    def initialize(@fragment)
      super("llm_text_fragment")
    end
  end

  class LLMText < Event
    getter content : String

    def initialize(@content)
      super("llm_text")
    end
  end
end
