require "../../tools/built_in_function"
require "../runtime"

module Enkaidu
  # All built-in tools subclass `BuiltInFunction`
  abstract class SessionBuiltInFunction < LLM::LocalFunction
    # Use the runtime to access Enkaidu session management
    protected getter runtime : Runtime

    # Create an Enkaidu runtime-specific built-in function type.
    def initialize(@runtime, @settings = nil)
      super("Session Built-ins")

      # All built-in tools ask for a reason for the tool call so that Enkaidu can
      # show a friendly reason
      param "reason", required: true, type: Param::Type::Str,
        description: "In gerund form, describe briefly what you're working on that led you to call this tool."
    end

    # Define the method that is used to create the SessionBuiltInFunction::Runner
    macro runner(runner_type)
      # Return an instance of this function's Runner
      def new_runner : Runner
        {{runner_type}}.new(self)
      end
    end

    # This defines the runner for implementations of `SessionBuildInFunction`.
    abstract class Runner < LLM::Function::Runner
      protected getter func : SessionBuiltInFunction

      def initialize(@func); end

      # Create an error response as a JSON string
      protected def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
