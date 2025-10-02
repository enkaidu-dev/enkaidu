require "../content"

module MCPC
  enum Role
    Assistant
    User
  end

  class UnexpectedMessageRole < Exception
    def initialize(role)
      super "Unexpected MCP prompt message role: #{role || "nil"}"
    end
  end

  # Represents a message in a request to the LLM
  class PromptMessage
    include JSON::Serializable

    getter role : Role
    getter content : Content

    def initialize(@role, @content); end

    def self.import(json : JSON::Any)
      role = json["role"]?.try(&.as_s?)
      role = (role && Role.parse(role)) || raise UnexpectedMessageRole.new(role)

      type = json.dig("content", "type")
      content = case type
                when Content::Text::TYPE  then Content::Text.import(json["content"])
                when Content::Image::TYPE then Content::Image.import(json["content"])
                when Content::Audio::TYPE then Content::Audio.import(json["content"])
                else
                  raise UnexpectedContent.new(type)
                end

      PromptMessage.new(role, content)
    end
  end
end
