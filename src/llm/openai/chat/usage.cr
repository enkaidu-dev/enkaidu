require "json"

module LLM::OpenAI
  class Usage
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    getter prompt_tokens = 0
    getter completion_tokens = 0
    getter total_tokens = 0
  end
end
