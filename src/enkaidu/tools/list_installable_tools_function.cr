require "../../llm"
require "./session_built_in_function"

module Enkaidu
  class ListInstallableTools < SessionBuiltInFunction
    RESPONSE_INSTALLABLE_TOOLS = "installable_tools"
    RESPONSE_INSTRUCTION       = "instruction"

    name "list_installable_tools"
    side_effects SideEffects::None

    description <<-DESC
      Returns a list of installable tools. A tool must be installed before it can be called.
      DESC

    runner Runner

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < SessionBuiltInFunction::Runner(ListInstallableTools)
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        # List tools
        JSON.build do |json|
          json.object do
            json.field RESPONSE_INSTALLABLE_TOOLS do
              func.runtime.session.tools_catalog_builder(json)
            end
            json.field RESPONSE_INSTRUCTION, "IMPORTANT: YOU MUST install a tool from this list BEFORE you can call it."
          end
        end
      rescue ex
        error_response(ex.message)
      end
    end
  end
end
