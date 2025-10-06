require "./content"

module MCP
  # Represents text `content` within a message to the LLM
  class Content::Text < Content
    TYPE = "text"
    getter text : String

    def initialize(@text)
      super TYPE
    end

    def self.import(json : JSON::Any)
      self.new(json["text"].as_s)
    end
  end
end
