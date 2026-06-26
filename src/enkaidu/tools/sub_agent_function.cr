require "../../llm"
require "./session_built_in_function"

module Enkaidu
  # Defines a tool / function to make a single query to Enkaidu
  class SubAgentPromptFunction < SessionBuiltInFunction
    name "spawn_agent"

    # By itself, has no sideffects
    side_effects SideEffects::None

    description <<-DESC
    Submit a prompt to the LLM to process in a separate context window, and receive the result as `[query, response]`.
    Call the tool with a clean context (default), or include current session context so the sub-agent can use that information to process the prompt.

    **Use this tool whenever the task:**
    - would consume significant tokens (large codebases, long or many documents, multi-step research)
    - is self-contained and doesn't need the current session's history
    - benefits from a clean slate to avoid context pollution or confusion
    DESC

    param "prompt", type: Param::Type::Str, required: true,
      description: "The full instruction for the sub-agent."
    param "include_session_context", type: Param::Type::Bool, required: false,
      description: <<-PDESC
      Set to true only when the sub-agent can benefit from awareness of the current session.
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

        # Fork the session to process the prompt.
        # Since this is a tool call, exclude the last turn if keeping history
        # to (a) avoid an incomplete request in history, and (b) to avoid repeating the same
        # prompt that initiated this tool call.
        reply = func.runtime.session_manager.ask_forked_session(prompt,
          keep_history,
          exclude_last_turn: true)

        reply || error_response("Nil response")
      rescue ex
        error_response(ex.message)
      end
    end
  end
end
