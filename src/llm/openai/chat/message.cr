require "./content"

module LLM::OpenAI
  # Represents a message in a request to the LLM
  abstract class Message
    include JSON::Serializable

    use_json_discriminator "role", {tool:      Message::ToolCall,
                                    user:      Message::MultiContent,
                                    assistant: Message::Response}

    property role : String
  end
end

require "./message/*"
