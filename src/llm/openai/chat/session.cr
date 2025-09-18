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
  end
end
