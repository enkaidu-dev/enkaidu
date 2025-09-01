require "./built_in_function"

module Tools
  # A `ToolSet` hold a set of tools until they need to be instantiated
  class ToolSet
    getter name : String
    # Track the available tools
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
      @tool_names = nil
    end

    def each_tool_info(&)
      @tools.each do |name, fun_class|
        yield name, fun_class.description
      end
    end

    def tool_names
      @tool_names ||= @tools.keys
    end

    # Call this method to instantiate the tools held within this `ToolSet`, optionally
    # using a `selection` of tool names to limit the tools that get "produced".
    def produce(renderer : Enkaidu::SessionRenderer, selection : Enumerable(String)? = nil, & : LLM::Function ->)
      @tools.each_value do |fun_class|
        next if selection && !selection.includes?(fun_class.function_name)

        yield fun_class.new(renderer)
      end
    end
  end
end
