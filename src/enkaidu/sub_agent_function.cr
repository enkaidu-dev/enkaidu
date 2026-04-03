require "../llm"

module Enkaidu
  # Defines a tool / function to make a single query to Enkaidu
  class SubAgentPromptFunction < LLM::LocalFunction
    name "sub_agent"

    description <<-DESC
    Use a sub-agent to query / prompt the LLM in a separate session with an isolated context.
    The prompt is executed immediately and, upon completion, returns the outline (initial query, final response) of the session
    as an array of messages. Use this tool to perform tasks that require a lot of context that is
    best isolated from the current session's context. Sub-agents can invoke nested sub-agents to further manage
    the context and perform complex tasks.
    DESC

    param "prompt", type: Param::Type::Str, required: true,
      description: "The prompt to be executed by the sub-agent in an isolated context"

    # Accessible to the function's Runner
    protected getter session_manager : SessionManager

    def initialize(@session_manager)
      super("Session Built-ins")
    end

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < LLM::Function::Runner
      private getter func : SubAgentPromptFunction

      def initialize(@func); end

      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        prompt = args["prompt"]?.try(&.as_s?) || return error_response("Required `prompt` was not specified")
        prompt = prompt.strip
        return error_response("Required `prompt` was empty") if prompt.empty?

        func.session_manager.ask_forked_session(prompt) ||
          error_response("Nil response")
      rescue ex
        error_response(ex.message)
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end
    end

    # Return an instance of this function's Runner
    def new_runner : Runner
      Runner.new(self)
    end
  end
end
