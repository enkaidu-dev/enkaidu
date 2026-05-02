require "../llm"
require "../enkaidu/session_renderer"

module Tools
  # All built-in tools subclass `BuiltInFunction`
  abstract class BuiltInFunction < LLM::LocalFunction
    # Use the `renderer` for sending output
    getter renderer : Enkaidu::SessionRenderer

    # Create an built-in function instance with a `renderer` and optional `settings`.
    def initialize(@renderer, settings = nil)
      super("Enkaidu Built-ins", settings)

      # All built-in tools ask for a reason for the tool call so that Enkaidu can
      # show a friendly reason
      param "reason", required: true, type: Param::Type::Str,
        description: "Provide one sentence describing what you're trying to accomplish; use a gerund."
    end
  end
end
