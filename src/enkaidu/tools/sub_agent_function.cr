require "../../llm"
require "./session_built_in_function"

module Enkaidu
  # Defines a tool / function to make a single query to Enkaidu
  class SubAgentPromptFunction < SessionBuiltInFunction
    PARAM_PROMPT            = "prompt"
    PARAM_SESSION_CONTEXT   = "session_context"
    SETTING_MAX_AGENT_DEPTH = "max_agent_depth"

    name "spawn_agent"

    # By itself, has no sideeffects
    side_effects SideEffects::None

    description <<-DESC
      Submit a prompt to the LLM to process in a separate context window, and receive the result as [query, response].
      Call the tool with a clean context (default), or include current session context so the sub-agent can use that information.
      Use this tool when the task would consume significant tokens, is self-contained, or benefits from a clean slate to avoid context pollution.
      DESC

    param PARAM_PROMPT, type: Param::Type::Str, required: true,
      description: "The full instruction for the sub-agent."
    param PARAM_SESSION_CONTEXT, type: Param::Type::Bool, required: false,
      description: "Optional. Set to true to include the current session context in the sub-agent's context. Default is false."

    runner Runner

    protected def max_agent_depth
      @max_agent_depth ||= case value = settings.try(&.[SETTING_MAX_AGENT_DEPTH]?)
                           when Number, String then Int32.new(value).clamp(0, 5)
                           else                     2
                           end
    end

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < SessionBuiltInFunction::Runner(SubAgentPromptFunction)
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        keep_history = args[PARAM_SESSION_CONTEXT]?.try(&.as_bool?) || false
        prompt = args[PARAM_PROMPT]?.try(&.as_s?) || return error_response("Required `prompt` was not specified")
        prompt = prompt.strip
        session_manager = func.runtime.session_manager

        return error_response("Required `prompt` was empty") if prompt.empty?

        if session_manager.current.session.sub_agent_depth >= func.max_agent_depth
          return error_response("Agent depth limit reached. Solve the task yourself.")
        end

        # Fork the session to process the prompt.
        # Since this is a tool call, exclude the last turn if keeping history
        # to (a) avoid an incomplete request in history, and (b) to avoid repeating the same
        # prompt that initiated this tool call.

        reply = func.runtime.session_manager.ask_forked_session(prompt,
          keep_history,
          exclude_last_turn: true,
          sub_agent: true)

        reply || error_response("Nil response")
      rescue ex
        error_response(ex.message)
      end
    end
  end
end
