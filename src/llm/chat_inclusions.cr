require "./function"

module LLM
  private enum ContentType
    Text
    ImageData
    FileData
  end

  # This class is used to setup additional content for use with a `Chat#ask`.
  class ChatInclusions
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

    delegate empty?, size, each, to: @content
  end
end
