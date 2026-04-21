require "../llm"

module Enkaidu
  # Defines a tool / function to make a single query to Enkaidu
  class SubAgentPromptFunction < LLM::LocalFunction
    name "spawn_agent"

    description <<-DESC
    Run a prompt in a completely fresh, isolated context window and receive the result as `[query, response]`.

    **Use this tool whenever the task:**
    - would consume significant tokens (large codebases, long or many documents, multi-step research)
    - is self-contained and doesn't need the current session's history
    - benefits from a clean slate to avoid context pollution or confusion

    Sub-agents can invoke their own sub-agents for further decomposition. Prefer sub-agents over doing heavy work inline — they keep the main session focused and prevent context window exhaustion.
    DESC

    param "prompt", type: Param::Type::Str, required: true,
      description: "the full instruction for the sub-agent; be explicit, as it has no other context"
    param "include_caller_history", type: Param::Type::Bool, required: false,
      description: <<-PDESC
      set to true when the task requires awareness of the current session, e.g. summarizing the conversation, continuing a thread, or referencing prior decisions
      PDESC

    # All built-in tools ask for a reason for the tool call so that Enkaidu can
    # show a friendly reason
    param "reason", required: true, type: Param::Type::Str,
      description: "Provide a single sentence describing the task or reason for spawning this agent."

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
        keep_history = args["include_caller_history"]?.try(&.as_bool?) || false
        prompt = args["prompt"]?.try(&.as_s?) || return error_response("Required `prompt` was not specified")
        prompt = prompt.strip

        return error_response("Required `prompt` was empty") if prompt.empty?

        func.session_manager.ask_forked_session(prompt, keep_history) ||
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
