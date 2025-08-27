require "./built_in_function"

module Tools
  # A `ToolSet` hold a set of tools until they need to be instantiated
  class ToolSet
    getter name : String
    @tools = {} of String => BuiltInFunction.class

    # Create a new named toolset
    def self.create(name, &)
      toolset = self.new(name)
      with toolset yield
      toolset
    end

    private def initialize(@name); end

    # Call when creating a `ToolSet` to hold built-in function classes
    protected def hold(fun_class)
      name = fun_class.function_name
      @tools[name] = fun_class unless @tools.has_key?(name)
    end

    def each_tool_info(&)
      @tools.each do |name, fun_class|
        yield name, fun_class.description
      end
    end

    # Call this method to instantiate the tools held within this `ToolSet`
    def produce(renderer : Enkaidu::SessionRenderer, & : LLM::Function ->)
      @tools.each_value do |fun_class|
        yield fun_class.new(renderer)
      end
    end
  end
end
