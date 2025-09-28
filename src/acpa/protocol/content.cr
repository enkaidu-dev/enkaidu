require "./capabilities"

module ACPA
  abstract class ContentBlock < JsonRpc::Entity
    use_json_discriminator "type", {
      text: TextContent,
    }
    getter type : String
  end

  class TextContent < ContentBlock
    getter text : String

    def initialize(@text)
      super("text")
    end
  end
end
