require "./function"

module LLM
  alias ChatEvent = NamedTuple(type: String, content: JSON::Any)

  # `Chat` is an abstract class that serves as a base for creating various chat implementations.
  abstract class Chat
    private enum ContentType
      Text
      ImageData
      FileData
    end

    # This class is used to setup additional content for use with a `Chat#ask`.
    class Inclusions
      @content = [] of NamedTuple(type: ContentType, name: String, data: String)

      def initialize; end

      # Expects a data URL string
      def image_data(data_url : String, source_path : String) : Nil
        @content << {type: ContentType::ImageData, data: data_url, name: source_path}
      end

      # Expects some text
      def text(content : String, source_path : String) : Nil
        @content << {type: ContentType::Text, data: content, name: source_path}
      end

      # Expects base64-encoded data from a file
      def file_data(base64_content : String, source_path : String) : Nil
        @content << {type: ContentType::FileData, data: base64_content, name: source_path}
      end

      def each(&)
        @content.each { |item| yield item }
      end

      def each
        @content.each
      end
    end

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
      return if @tools_by_name[function.name]?
      @tools_by_name[function.name] = function
      by_origin = @tools_by_origin[function.origin]? ||
                  (@tools_by_origin[function.origin] = {} of String => Function)
      by_origin[function.name] = function
    end

    def without_tool(function_name)
      return unless function = @tools_by_name[function_name]?

      if by_origin = @tools_by_origin[function.origin]?
        by_origin.delete(function_name)
      end
      @tools_by_name.delete(function_name)
    end

    def find_tool?(name)
      @tools_by_name[name]?
    end

    def each_tool_origin(&)
      @tools_by_origin.each { |name, by_origin| yield(name) unless by_origin.empty? }
    end

    def each_tool(origin : String? = nil, &)
      return unless tools = (origin ? @tools_by_origin[origin] : @tools_by_name)
      tools.each_value do |tool|
        yield tool
      end
    end

    def each_tool
      @tools_by_name.each_value
    end

    abstract def ask(content : String, attach : Inclusions? = nil, & : ChatEvent ->) : Nil

    abstract def save_session(io : IO | JSON::Builder) : Nil
  end
end
