require "json"

require "./param"

module LLM
  # Defines custom function tool
  abstract class Function
    abstract def name : String
    abstract def description : String

    # A short title about the origin of the function
    getter origin : String = "Unknown"

    # This defines the runner that is instantiated to
    # execute the function.
    abstract class Runner
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      abstract def execute(args : JSON::Any) : String
    end

    # Return an instance of this function's Runner
    abstract def new_runner : Runner

    # Call this method to clone and execute this function
    def run(args : JSON::Any) : String
      self.new_runner.execute(args)
    end

    # The input schema for the parameters to this function, as a String.
    def input_json_schema : String
      JSON.build do |json|
        input_json_schema(json)
      end
    end

    # The input schema for the parameters to this function, into the JSON builder.
    abstract def input_json_schema(json : JSON::Builder)
  end
end
