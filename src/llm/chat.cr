require "./function"

module LLM
  alias ChatEvent = NamedTuple(type: String, content: JSON::Any)

  abstract class Chat
    getter model : String | Nil = nil
    getter system_message : String | Nil = nil
    getter? debug = false
    getter? streaming = false

    def initialize
      @tools = {} of String => LLM::Function
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

    def with_tool(function : LLM::Function)
      @tools[function.name] = function
    end

    def find_tool?(name)
      @tools[name]?
    end

    def each_tool(&)
      @tools.each_value do |t|
        yield t
      end
    end

    abstract def ask(content : String, & : ChatEvent ->)
  end
end
