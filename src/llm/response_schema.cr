require "json"

module LLM
  # Represents the response JSON schema that can be given to a chat request
  class ResponseSchema
    include JSON::Serializable

    getter name : String
    getter description : String
    getter? strict = false
    getter schema : JSON::Any
  end
end
