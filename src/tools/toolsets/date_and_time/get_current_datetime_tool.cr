require "json"
require "../../built_in_function"

module Tools::DateAndTime
  # The `GetCurrentDatetimeTool` class defines a tool for fetching the current date and time.
  class GetCurrentDatetimeTool < BuiltInFunction
    name "get_current_datetime"

    description "Returns the current date and time as a string in ISO 8601 format."

    runner Runner

    class Runner < LLM::Function::Runner
      def execute(args : JSON::Any) : String
        current_datetime = Time.utc.to_s("%FT%T%:z")

        success_response(current_datetime)
      end

      # Create a success response as a JSON string
      def success_response(current_datetime)
        {
          current_datetime: current_datetime,
        }.to_json
      end
    end
  end
end
