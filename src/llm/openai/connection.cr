require "./chat"
require "../connection"

module LLM::OpenAI
  # `Connection` is a class extending `LLM::Connection` to implement specific behaviors
  # for OpenAI's chat services.
  class Connection < LLM::Connection
    def new_chat(&) : LLM::Chat
      chat = Chat.new(self)
      with chat yield
      chat
    end

    def url : String
      ENV.fetch("OPENAI_ENDPOINT", "https://api.openai.com")
    end

    def api_key : String
      ENV.fetch("OPENAI_API_KEY", nil) || raise MissingAPIKey.new("OpenAI connections require an API key.")
    end

    def model
      super || ENV["OPENAI_MODEL"]?
    end

    protected def path : String
      "/v1/chat/completions"
    end

    protected def headers : HTTP::Headers
      HTTP::Headers{
        "Content-Type"  => "application/json",
        "Connection"    => "keep-alive",
        "Authorization" => "Bearer #{api_key}",
      }
    end
  end
end
