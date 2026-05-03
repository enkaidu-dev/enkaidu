require "../../llm"
require "./session_built_in_function"

module Enkaidu
  class ListInstallableTools < SessionBuiltInFunction
    name "list_installable_tools"

    description <<-DESC
    Obtain a list of available tools that you can install. Use the list to determine the tools that will help with
    your task. IMPORTANT: YOU MUST install a tool from this list BEFORE you can call it.
    DESC

    runner Runner

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < SessionBuiltInFunction::Runner
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        # List tools
        JSON.build do |json|
          json.object do
            json.field "installable_tools" do
              func.runtime.session.tools_catalog_builder(json)
            end
            json.field "instruction", "IMPORTANT: YOU MUST install a tool from this list BEFORE you can call it."
          end
        end
      rescue ex
        error_response(ex.message)
      end
    end
  end
end
