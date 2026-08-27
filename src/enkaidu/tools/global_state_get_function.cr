require "../../llm"
require "./session_built_in_function"

module Enkaidu
  # Defines a tool / function to make a single query to Enkaidu
  class GlobalStateGetFunction < SessionBuiltInFunction
    name "get_global_state"

    # By itself, has no sideffects
    side_effects SideEffects::None

    description <<-DESC
      Get the values for one or more keys within a namespace in the global state available across sessions and turns.
      A monotonically increasing revision counter per namespace is updated for every change to a key in that namespace.
      DESC

    param "namespace", type: Param::Type::Str, required: true,
      description: "A namespace is a container of key/value pairs"
    param "keys", type: Param::Type::Arr, required: true,
      description: "An array of one or more keys for which to retrieve the values. Unknown keys will return a `null` value."

    runner Runner

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < SessionBuiltInFunction::Runner
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        namespace = args["namespace"]?.try(&.as_s?) || return error_response("Required `namespace` was not specified")
        json_keys = args["keys"]?.try(&.as_a?) || return error_response("Required `keys` was not specified")

        keys = convert_json_array(json_keys)

        global_state = func.runtime.session_manager.global_state
        key_values = {} of String => String?
        keys.each do |key|
          key_values[key] = global_state.get?(namespace, key)
        end
        success_response(namespace, global_state.revision(namespace), key_values)
      rescue ex
        error_response(ex.message)
      end

      # Create a success response as a JSON string
      private def success_response(namespace, revision, key_values)
        {
          namespace => {
            "revision" => revision,
          },
          "key_values" => key_values,
        }.to_json
      end

      private def convert_json_array(json_array : Array(JSON::Any)) : Array(String)
        json_array.map do |json_any|
          unless str = json_any.as_s?
            raise ArgumentError.new("Expected keys to be strings, not: #{json_any}")
          end
          str
        end
      end
    end
  end
end
