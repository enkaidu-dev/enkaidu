require "../../llm"
require "./session_built_in_function"

module Enkaidu
  class InstallToolsFunction < SessionBuiltInFunction
    PARAM_TOOLS            = "tools"
    RESPONSE_TOOL          = "tool"
    RESPONSE_INSTALLED     = "installed"
    RESPONSE_NOT_INSTALLED = "not_installed"

    name "install_tools"
    side_effects SideEffects::None

    description <<-DESC
      Install one or more tools from the list of installable tools. Tool names are unique across toolsets.
      DESC

    param PARAM_TOOLS, type: Param::Type::Arr, required: true,
      description: "List of one or more tools to install so they are available to call afterwards"

    runner Runner

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < SessionBuiltInFunction::Runner(InstallToolsFunction)
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        tools_arr = args[PARAM_TOOLS]?.try(&.as_a?) || return error_response("Required `tools` was not specified")
        tool_names = tools_arr.map(&.as_s)
        if user_confirms?(tool_names)
          loaded = func.runtime.session.load_tools_across_toolsets(tool_names)
          not_loaded = tool_names.reject { |name| loaded.any?(&.[RESPONSE_TOOL].==(name)) }
          if loaded.size.zero?
            error_response("None of the tools were installed.")
          elsif not_loaded.size > 0
            {RESPONSE_STATUS        => "Partial",
             RESPONSE_INSTALLED     => loaded,
             RESPONSE_NOT_INSTALLED => not_loaded,
             RESPONSE_MESSAGE       => "Some tools were installed, some were not."}.to_json
          else
            {RESPONSE_STATUS    => "Complete",
             RESPONSE_INSTALLED => loaded,
             RESPONSE_MESSAGE   => "All the tools were installed"}.to_json
          end
        else
          error_response("Declined: The user did NOT approve the use of one or more of these tools?")
        end
      rescue ex
        error_response(ex.message)
      end

      def user_confirms?(tool_names)
        description = "The agent's AI model wants to load the following tools:"
        func.runtime.renderer.user_confirm_security_question?(description, tool_names)
      end
    end
  end
end
