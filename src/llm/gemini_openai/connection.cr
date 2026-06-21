require "http/client"
require "uri"

require "../openai"

module LLM::GeminiOpenAI
  # `Connection` is a class that extends from `OpenAI::Connection` to provide
  # specialized connection handling for Azure OpenAI services.
  class Connection < OpenAI::Connection
    def api_key
      ENV["GEMINI_API_KEY"]
    end

    protected def url : String
      ENV["GEMINI_OPENAI_ENDPOINT"]? || "https://generativelanguage.googleapis.com"
    end

    protected def path : String
      ENV["GEMINI_OPENAI_CHAT_PATH"]? || "/v1beta/openai/chat/completions"
    end

    protected def headers : HTTP::Headers
      HTTP::Headers{
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{api_key}",
      }
    end
  end
end
