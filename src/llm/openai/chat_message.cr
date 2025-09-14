require "json"

module LLM::OpenAI
  # Represents `content` within a message to the LLM
  abstract class Content
    include JSON::Serializable

    use_json_discriminator "type", {text:      Content::Text,
                                    image_url: Content::ImageUrl,
                                    file:      Content::FileData}

    property type : String
  end

  # Represents text `content` within a message to the LLM
  class Content::Text < Content
    include JSON::Serializable

    property text : String

    def initialize(@text)
      @type = "text"
    end
  end

  # Represents image `content` within a message to the LLM
  class Content::ImageUrl < Content
    include JSON::Serializable

    property image_url = {} of String => String

    def initialize(url)
      @type = "image_url"
      @image_url["url"] = url
    end
  end

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

  # Represents a message in a request to the LLM
  abstract class Message
    include JSON::Serializable

    use_json_discriminator "role", {tool:      Message::ToolCall,
                                    user:      Message::MultiContent,
                                    assistant: Message::Response}

    property role : String
  end

  # Represents a tool-call result message in a request to the LLM
  class Message::ToolCall < Message
    include JSON::Serializable

    property tool_call_id : String
    property name : String
    property content : String

    def initialize(@tool_call_id, @name, @content)
      @role = "tool"
    end
  end

  # Represents a multi-content message in a request to the LLM
  class Message::MultiContent < Message
    include JSON::Serializable

    property content = [] of Content

    def initialize(prompt : String, attach : Chat::Inclusions? = nil)
      @role = "user"
      text(prompt)
      if more = attach
        more.each do |content|
          case content[:type]
          when .text?       then text(content[:data])
          when .image_data? then image_url(content[:data])
          when .file_data?  then file_data(content[:data], content[:name])
          end
        end
      end
    end

    private def text(text : String)
      content << Content::Text.new(text)
    end

    private def image_url(url : String)
      content << Content::ImageUrl.new(url)
    end

    private def file_data(base64_data : String, file_name : String)
      content << Content::FileData.new(base64_data: base64_data, file_name: file_name)
    end
  end

  class Usage
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    getter prompt_tokens = 0
    getter completion_tokens = 0
    getter total_tokens = 0
  end

  # Represents a response message from the LLM
  class Message::Response < Message
    include JSON::Serializable

    property content : String?

    @[JSON::Field(ignore_serialize: ((toolcalls = @tool_calls).nil? || toolcalls.empty?))]
    property tool_calls : Array(JSON::Any)?

    # Sidecar to response message so we can keep the usage together with it.
    # Not serialized.
    @[JSON::Field(ignore: true)]
    property usage : Usage? = nil

    def initialize(@content, @tool_calls = nil)
      @role = "assistant"
    end
  end
end
