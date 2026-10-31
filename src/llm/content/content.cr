require "json"

require "../chat"

module LLM
  # Represents `content` within a message to the LLM
  abstract class Content
    include JSON::Serializable

    use_json_discriminator "type", {text:      Content::Text,
                                    image_url: Content::ImageUrl,
                                    file:      Content::FileData}

    property type : String

    # Emit this content as one or more `ChatEvent` objects
    abstract def emit(& : ChatEvent ->) : Nil
  end
end

require "./text"
require "./image_url"
require "./file_data"
require "./input_audio"
