require "../llm"
require "../enkaidu/session_renderer"

module Tools
  # Define a settings Hash with fixed value types for use with tools
  class Settings < Hash(String, String | Int64 | Bool | Array(String) | Array(Int64)); end

  # All built-in tools subclass `BuiltInFunction`
  abstract class BuiltInFunction < LLM::LocalFunction
    # Use the `renderer` for sending output
    getter renderer : Enkaidu::SessionRenderer

    # Settings available to subclasses
    protected getter settings : Settings?

    # Create an built-in function instance with a `renderer` and optional `settings`.
    def initialize(@renderer, @settings = nil)
      super("Enkaidu Built-ins")

      # All built-in tools ask for a reason for the tool call so that Enkaidu can
      # show a friendly reason
      param "reason", required: true, type: Param::Type::Str,
        description: "Provide one sentence describing the reason for this tool call."
    end
  end
end
