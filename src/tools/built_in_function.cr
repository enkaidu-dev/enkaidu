require "../llm"
require "../enkaidu/session_renderer"
require "./param_names"

module Tools
  # All built-in tools subclass `BuiltInFunction`
  abstract class BuiltInFunction < LLM::LocalFunction
    include Tools::ParamNames

    REASON_DESCRIPTION = "A concise summary describing your intent, as a full capitalized sentence using a gerund."

    # Use the `renderer` for sending output
    getter renderer : Enkaidu::SessionRenderer

    # Create an built-in function instance with a `renderer` and optional `settings`.
    def initialize(@renderer, settings = nil)
      super("Enkaidu Built-ins", settings)

      # All built-in tools ask for a reason for the tool call so that Enkaidu can
      # show a friendly reason
      param PARAM_REASON, required: true, type: Param::Type::Str,
        description: REASON_DESCRIPTION
    end
  end
end
