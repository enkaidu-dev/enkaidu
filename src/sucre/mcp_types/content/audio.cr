require "./media"

module MCP
  # Represents audio content in a prompt message
  class Content::Audio < Content::Media
    TYPE = "audio"

    def initialize(data, mime_type)
      super TYPE, data, mime_type
    end
  end
end
