require "http/client"
require "uri"

require "../openai"

module LLM::Ollama
  # `Connection` is a class that extends from `OpenAI::Connection` to provide
  # specialized connection handling with local AI models run using Ollama.
  class Connection < OpenAI::Connection
    protected def url : String
      ENV.fetch("OLLAMA_ENDPOINT", "http://localhost:11434")
    end

    def model
      super || ENV["OLLAMA_MODEL"]?
    end

    def api_key : String
      ENV.fetch("OLLAMA_API_KEY", "ollama")
    end

    protected def path : String
      "/v1/chat/completions"
    end
  end
end
