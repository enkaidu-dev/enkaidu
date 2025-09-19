require "json"

require "./message"
require "./usage"

module LLM::OpenAI
  # The serializable chat session keeps all wrapped messages to save
  # the additional information when saving the session.
  class Session
    # This wrapper is used to keep the `Message` and additional information
    # that we want to save when available.
    class MessageWrap
      include JSON::Serializable

      getter message : Message
      getter usage : Usage?

      def initialize(@message, @usage); end
    end

    # The session itself is serializable so we can save a chat session
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    getter format : String

    def initialize
      @format = self.class.name
      @messages = [] of MessageWrap
    end

    def append_message(msg, usage : Usage? = nil)
      @messages << MessageWrap.new(msg, usage)
    end

    # This yields each `Message` in the session
    def each_message(&)
      @messages.each do |msgplus|
        yield msgplus.message
      end
    end

    # Returns the most recent usage information
    def last_usage : Usage?
      @messages.reverse_each do |msg|
        if usage = msg.usage
          return usage
        end
      end
      nil
    end

    # Emit the last N request responses. Always tries to emit the query before the response. May include
    # tool calls as a result. Use N=-1 to list all
    def tail_chats(num = -1, &)
      return if num.zero?

      start_index = num < 0 ? 0 : @messages.size - 1
      # Find last num'th user message
      num.times do
        break if start_index.nil? || start_index.zero?
        start_index = @messages.rindex do |msg|
          msg.message.is_a? Message::MultiContent
        end
      end
      start_index = 0 if start_index.nil?

      # yield each one via it's emitter because some
      # emit more than one
      @messages.each(start: start_index, count: @messages.size - start_index) do |msg|
        msg.message.emit { |chat_ev| yield chat_ev }
      end
    end
  end
end
