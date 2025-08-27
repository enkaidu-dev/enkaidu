require "../llm"
require "../enkaidu/session_renderer"

module Tools
  # All built-in tools subclass `BuiltInFunction`
  abstract class BuiltInFunction < LLM::LocalFunction
    getter renderer : Enkaidu::SessionRenderer

    def initialize(@renderer)
      super("Enkaidu Built-ins")
    end
  end
end
