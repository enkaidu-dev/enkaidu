require "../content.cr"

module LLM::OpenAI
  # Represents file `content` within a message to the LLM
  class Content::FileData < Content
    property file = {} of String => String

    def initialize(base64_data, file_name)
      @type = "file"
      @file["file_data"] = base64_data
      @file["filename"] = file_name
    end

    # Emit this content as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      yield({type: "query/file_data", content: JSON::Any.new(file["filename"])})
    end
  end
end
