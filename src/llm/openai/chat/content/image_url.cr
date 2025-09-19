require "../content"

module LLM::OpenAI
  # Represents image `content` within a message to the LLM
  class Content::ImageUrl < Content
    property image_url = {} of String => String

    def initialize(url)
      @type = "image_url"
      @image_url["url"] = url
    end

    # Emit this content as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      yield({type: "query/image_url", content: JSON::Any.new(@image_url["url"])})
    end
  end
end
