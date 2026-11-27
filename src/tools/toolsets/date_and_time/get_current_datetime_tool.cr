require "json"
require "../../built_in_function"

module Tools::DateAndTime
  # The `GetCurrentDatetimeTool` class defines a tool for fetching the current date and time.
  class GetCurrentDatetimeTool < BuiltInFunction
    name "date"

    side_effects SideEffects::None

    description "Returns the current date and time as a string in ISO 8601 format."

    runner Runner

    RESPONSE_DATE     = "date"
    RESPONSE_TIME     = "time"
    RESPONSE_TZ       = "tz"
    RESPONSE_LOCAL    = "local"
    RESPONSE_ISO_8601 = "iso_8601"

    class Runner < LLM::Function::Runner
      def execute(args : JSON::Any) : String
        local = Time.local

        success_response(local)
      end

      # Create a success response as a JSON string
      def success_response(local : Time)
        {
          RESPONSE_LOCAL    => {
            RESPONSE_DATE   => local.to_s("%Y-%m-%d"),
            RESPONSE_TIME   => local.to_s("%H:%M:%S %:z"),
            RESPONSE_TZ     => local.to_s("%Z"),
          },
          RESPONSE_ISO_8601 => local.to_rfc3339,
        }.to_json
      end
    end
  end
end
