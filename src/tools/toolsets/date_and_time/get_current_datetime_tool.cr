require "json"
require "../../built_in_function"

module Tools::DateAndTime
  # The `GetCurrentDatetimeTool` class defines a tool for fetching the current date and time.
  class GetCurrentDatetimeTool < BuiltInFunction
    name "get_current_datetime"

    side_effects SideEffects::None

    description "Returns the current date and time as a string in ISO 8601 format."

    runner Runner

    class Runner < LLM::Function::Runner
      def execute(args : JSON::Any) : String
        local = Time.local

        success_response(local)
      end

      # Create a success response as a JSON string
      def success_response(local : Time)
        {
          local: {
            date: local.to_s("%Y-%m-%d"),
            time: local.to_s("%H:%M:%S %:z"),
            tz:   local.to_s("%Z"),
          },
          iso_8601: local.to_rfc3339,
        }.to_json
      end
    end
  end
end
