require "./param"

module LLM
  # Subclass to define custom tools
  abstract class Function
    abstract def name : String
    abstract def description : String

    # one list per class; do not edit
    @@params = [] of Param

    # Iterate through each parameter
    def self.each_param(&)
      @@params.each do |p|
        yield p
      end
    end

    # Set the name for the function.
    macro name(str)
      # The name of the function
      def self.function_name : String
        {{str}}
      end

      # The name of the function
      def name : String
        {{str}}
      end
    end

    # Set the description for the function.
    macro description(str)
      # The description of the function.
      def self.description : String
        {{str}}
      end

      # The description of the function.
      def description : String
        {{str}}
      end
    end

    # Define a parameter for this LLM Function.
    macro param(name, description, type = LLM::ParamType::Str, required = false)
      @@params << LLM::Param.new({{name}}, {{type}}, {{description}}, {{required}})
    end

    # Call to create and run a function instance
    def self.run(args : JSON::Any) : String
      self.new.execute(args)
    end

    # Implement this method to handle the LLM function call, and return a
    # String with the JSON value.
    abstract def execute(args : JSON::Any) : String
  end
end
