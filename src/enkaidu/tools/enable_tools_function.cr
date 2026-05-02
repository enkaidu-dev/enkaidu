require "../../llm"
require "./session_built_in_function"

module Enkaidu
  class EnableToolsFunction < SessionBuiltInFunction
    name "enable_tools_from_catalog"

    description <<-DESC
    Enable one more tools (from a toolset) that you want to use from the tools catalog.
    DESC

    param "toolset", type: Param::Type::Str, required: true,
      description: "The name of the toolset from which to enable tools"
    param "tools", type: Param::Type::Arr, required: true,
      description: "List of one or more tool names from the toolset to enable"

    runner Runner

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < SessionBuiltInFunction::Runner
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        toolset_name = args["toolset"]?.try(&.as_s?) || return error_response("Required `toolset` was not specified")
        tools_arr = args["tools"]?.try(&.as_a?) || return error_response("Required `tools` was not specified")
        tool_names = tools_arr.map(&.as_s)
        func.runtime.session.load_toolset_by(toolset_name, select_tools: tool_names)
        {status: "Success"}.to_json
      rescue ex
        error_response(ex.message)
      end
    end
  end
end
