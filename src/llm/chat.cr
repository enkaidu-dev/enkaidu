require "./function"

module LLM
  alias ChatEvent = NamedTuple(type: String, content: JSON::Any)

  abstract class Chat
    getter model : String | Nil = nil
    getter system_message : String | Nil = nil
    getter? debug = false
    getter? streaming = false

    def initialize
      @tools_by_name = {} of String => Function
      @tools_by_origin = {} of String => Hash(String, Function)
    end

    def with_debug
      @debug = true
    end

    def with_streaming
      @streaming = true
    end

    def with_model(model : String)
      @model = model
    end

    def with_system_message(content : String)
      @system_message = content
    end

    def with_tool(function : Function)
      unless @tools_by_name[function.name]?
        @tools_by_name[function.name] = function
        by_origin = @tools_by_origin[function.origin]? ||
                    (@tools_by_origin[function.origin] = {} of String => Function)
        by_origin[function.name] = function
      end
    end

    def find_tool?(name)
      @tools_by_name[name]?
    end

    def each_tool_origin(&)
      @tools_by_origin.each_key { |origin| yield origin }
    end

    def each_tool(origin : String? = nil, &)
      if tools = (origin ? @tools_by_origin[origin] : @tools_by_name)
        tools.each_value do |tool|
          yield tool
        end
      end
    end

    def each_tool
      @tools_by_name.each_value
    end

    abstract def ask(content : String, & : ChatEvent ->)
  end
end
