require "../../llm"
require "./session_built_in_function"

module Enkaidu
  class CatalogToolsFunction < SessionBuiltInFunction
    name "list_tools_catalog"

    description <<-DESC
    Obtain a list of tools from the catalog of tools. Use the list to determine those that might help with
    your task and ask the user to load those before continuing.
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
            json.field "tools_catalog" do
              func.runtime.session.tools_catalog_builder(json)
            end
          end
        end
      rescue ex
        error_response(ex.message)
      end
    end
  end
end
