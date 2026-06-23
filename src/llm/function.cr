require "json"

module LLM
  # Defines custom function tool
  abstract class Function
    @[Flags]
    enum SideEffects
      FileRead
      FileWrite
      FileMove
      FileDelete
      DirRead
      DirWrite
      DirMove
      DirDel
      NetRead
      NetWrite
      CommandExec

      # Returns true if side-effects are read-only.
      def readonly?
        (self & ~(FileRead | DirRead | NetRead)).to_u32.zero?
      end

      # Return true if accesses network
      def network?
        net_read? || net_write?
      end

      # Return a comma-separated value string of flags, or `None`
      def value_string
        String.build do |str_io|
          ix = 0
          self.each do |val|
            str_io << ", " if ix.positive?
            str_io << val
            ix += 1
          end
          str_io << "None" if ix.zero?
        end
      end
    end

    # Define a settings Hash with fixed value types for use with functions
    class Settings < Hash(String, String | Int64 | Bool | Array(String) | Array(Int64)); end

    abstract def name : String
    abstract def description : String
    abstract def summary : String

    def self.side_effects : SideEffects
      SideEffects::All
    end

    def side_effects
      self.class.side_effects
    end

    # A short title about the origin of the function
    getter origin : String = "Unknown"
    # Optional settings passed to a function that supports them
    getter settings : Settings?

    def initialize(@origin, @settings = nil); end

    # Returns true if this tools side-effects are read-only.
    def readonly?
      side_effects.readonly?
    end

    # Internal use only
    @summary : String?
    @@summary : String?

    # The summary of the description; splits by '.' and then `\n' to return first entry.
    def summary : String
      @summary ||= description.split('.', limit: 2).first.split('\n', limit: 2).first
    end

    # The static summary of the description; splits by '.' and then `\n' to return first entry.
    def self.summary : String
      @@summary ||= description.split('.', limit: 2).first.split('\n', limit: 2).first
    end

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
