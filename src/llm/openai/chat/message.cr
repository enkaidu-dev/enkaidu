require "./content"

module LLM::OpenAI
  # Represents a message in a request to the LLM
  abstract class Message
    include JSON::Serializable

    use_json_discriminator "role", {tool:      Message::ToolCall,
                                    user:      Message::MultiContent,
                                    assistant: Message::Response}

    property role : String

    # Emit this message as one or more `ChatEvent` objects
    abstract def emit(& : ChatEvent ->) : Nil

    # Used to encode message for sending to LLM. Can't use regular
    # to_json since we need to handle some special cases for the protocol
    # but we want to serialize whole entry for saving / restoring.
    # This starts the object and calls `protocol_fields_to_json`.
    # Do not override!
    def to_protocol_json(builder : JSON::Builder)
      builder.object do
        protocol_fields_to_json(builder)
      end
    end

    # Override this to add your fields after calling `super`
    protected def protocol_fields_to_json(json : JSON::Builder)
      json.field "role", role
    end
  end
end

require "./message/*"
