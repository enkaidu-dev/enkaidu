require "json"
require "mime"

module MCPC
  class UnexpectedContent < Exception
    def initialize(type)
      super "Unexpected MCP message content: \"#{type}\""
    end
  end

  class InvalidContentProperty < Exception; end

  # Represents `ContentBlock` per MCP protocol schema
  abstract class Content
    include JSON::Serializable

    use_json_discriminator "type", {text:  Content::Text,
                                    image: Content::Image,
                                    audio: Content::Audio}

    getter type : String

    def initialize(@type); end
  end
end

require "./content/*"
