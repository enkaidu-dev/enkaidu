require "./function"

module LLM
  # Defines a subclass of Function that can be used to
  # implement local (in-code) tools / functions easily
  abstract class LocalFunction < Function
    # one list per class; do not edit
    @@params = [] of Param

    def initialize
      @origin = "Enkaidu / Built-in"
    end

    # Iterate through each parameter
    def each_param(& : LLM::Param ->)
      @@params.each do |param|
        yield param
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

    # Define the method that is used to create the Runner
    macro runner(runner_type)
      # Return an instance of this function's Runner
      def new_runner : Runner
        {{runner_type}}.new
      end
    end
  end
end
