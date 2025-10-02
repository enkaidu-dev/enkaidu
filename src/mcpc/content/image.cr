require "../content"
require "./media"

module MCPC
  # Represents image `content` within a message to the LLM
  class Content::Image < Content::Media
    TYPE = "image"

    def initialize(data, mime_type)
      super TYPE, data, mime_type
    end
  end
end
