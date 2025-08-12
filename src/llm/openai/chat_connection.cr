require "./chat"
require "../chat_connection"

module LLM::OpenAI
  class ChatConnection < LLM::ChatConnection
    def initialize
      @url = ENV["OPENAI_ENDPOINT"]
      super()

      @api_key = ENV["OPENAI_API_KEY"] if ENV.includes?("OPENAI_API_KEY")
      @model = ENV["OPENAI_MODEL"]
    end

    def new_chat(&) : LLM::Chat
      chat = Chat.new(self)
      with chat yield
      chat
    end

    def url : String
      @url
    end

    protected def path : String
      "/v1/chat/completions"
    end

    protected def headers : HTTP::Headers
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }

      headers["Authorization"] = "Bearer #{@api_key}" unless @api_key.nil?

      headers
    end
  end
end
