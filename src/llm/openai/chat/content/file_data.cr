require "../content.cr"

module LLM::OpenAI
  # Represents file `content` within a message to the LLM
  class Content::FileData < Content
    include JSON::Serializable

    property file = {} of String => String

    def initialize(base64_data, file_name)
      @type = "file"
      @file["file_data"] = base64_data
      @file["filename"] = file_name
    end
  end
end
