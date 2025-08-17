require "http/client"
require "uri"

require "../openai"

module LLM::Ollama
  class ChatConnection < OpenAI::ChatConnection
    protected def url : String
      ENV.fetch("OLLAMA_ENDPOINT", "http://localhost:11434")
    end

    protected def path : String
      "/v1/chat/completions"
    end

    protected def headers : HTTP::Headers
      HTTP::Headers{
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer ollama",
      }
    end
  end
end
