require "http/client"
require "uri"

require "../openai"

module LLM::GoogleAIStudio
  # `Connection` is a class that extends from `OpenAI::Connection` to provide
  # specialized connection handling for Azure OpenAI services.
  class Connection < OpenAI::Connection
    def initialize
      # Does not support Responses protocol
      super(ProtocolKind::ChatCompletions)
    end

    private API_KEY_ENV_NAME = "GOOGLE_AI_API_KEY"

    def api_key : String
      ENV.fetch(API_KEY_ENV_NAME, nil) || raise MissingAPIKey.new("Google AI Studio requires an API key, Missing env var: #{API_KEY_ENV_NAME}")
    end

    protected def url : String
      ENV["GOOGLE_AI_ENDPOINT"]? || "https://generativelanguage.googleapis.com"
    end

    protected def path : String
      ENV["GOOGLE_AI_OPENAI_CHAT_PATH"]? || "/v1beta/openai/chat/completions"
    end

    protected def headers : HTTP::Headers
      HTTP::Headers{
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{api_key}",
      }
    end
  end
end
