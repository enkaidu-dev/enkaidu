require "./chat"
require "../chat_connection"

module LLM::OpenAI
  class ChatConnection < LLM::ChatConnection
    def new_chat(&) : LLM::Chat
      chat = Chat.new(self)
      with chat yield
      chat
    end

    def url : String
      ENV["OPENAI_ENDPOINT"]
    end

    def api_key : String | Nil
      ENV["OPENAI_API_KEY"] if ENV.includes?("OEPNAI_API_KEY")
    end

    def model
      ENV["OPENAI_MODEL"]
    end

    protected def path : String
      "/v1/chat/completions"
    end

    protected def headers : HTTP::Headers
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }

      headers["Authorization"] = "Bearer #{api_key}" unless api_key.nil?

      headers
    end
  end
end
