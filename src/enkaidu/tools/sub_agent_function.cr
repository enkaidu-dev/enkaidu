require "../../llm"
require "./session_built_in_function"

module Enkaidu
  # Defines a tool / function to make a single query to Enkaidu
  class SubAgentPromptFunction < SessionBuiltInFunction
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
      description: "The full instruction for the sub-agent; be explicit, especially when not including history."
    param "include_caller_history", type: Param::Type::Bool, required: false,
      description: <<-PDESC
      Set to true onlywhen the task requires awareness of the current session, e.g. summarizing the conversation,
      continuing a thread, or referencing prior decisions.
      PDESC

    runner Runner

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < SessionBuiltInFunction::Runner
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        keep_history = args["include_caller_history"]?.try(&.as_bool?) || false
        prompt = args["prompt"]?.try(&.as_s?) || return error_response("Required `prompt` was not specified")
        prompt = prompt.strip

        return error_response("Required `prompt` was empty") if prompt.empty?

        func.runtime.session_manager.ask_forked_session(prompt, keep_history) ||
          error_response("Nil response")
      rescue ex
        error_response(ex.message)
      end
    end
  end
end
