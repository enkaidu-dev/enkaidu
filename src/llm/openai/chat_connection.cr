require "./chat"
require "../chat_connection"

module LLM::OpenAI
  abstract class ChatConnection < LLM::ChatConnection
    def new_chat(&) : LLM::Chat
      chat = Chat.new(self)
      with chat yield
      chat
    end
  end
end
