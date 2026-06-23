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

    def each_tool_class(readonly = false, &)
      @tools.each do |name, fun_class|
        if !readonly || fun_class.side_effects.readonly?
          yield name, fun_class
        end
      end
    end

    def each_tool_info(readonly = false, &)
      @tools.each do |name, fun_class|
        if !readonly || fun_class.side_effects.readonly?
          yield name, fun_class.description
        end
      end
    end

    def tool_names
      @tool_names ||= @tools.keys
    end

    # Call this method to retrieve built-in tool/function classes
    # from this `ToolSet`, optionally using a `selection` of tool names to filter the tools
    def retrieve(readonly = false, selection : Enumerable(String)? = nil,
                 & : BuiltInFunction.class ->)
      @tools.each_value do |fun_class|
        next if readonly && !fun_class.side_effects.readonly?
        next if selection && !selection.includes?(fun_class.function_name)

        yield fun_class
      end
    end
  end
end
