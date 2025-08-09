require "./param"

module LLM
  # Defines custom function tool
  abstract class Function
    abstract def name : String
    abstract def description : String
    abstract def each_param(& : LLM::Param ->)

    # This defines the runner that is instantiated to
    # execute the function.
    abstract class Runner
      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      abstract def execute(f : Function, args : JSON::Any) : String
    end

    # Return an instance of this function's Runner
    abstract def new_runner : Runner

    # Call this method to clone and execute this function
    def run(args : JSON::Any) : String
      self.new_runner.execute(self, args)
    end
  end
end
