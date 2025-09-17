require "json"

require "./message"
require "./usage"

module LLM::OpenAI
  # The serializable chat session keeps all wrapped messages to save
  # the additional information when saving the session.
  private class Session
    # This wrapper is used to keep the `Message` and additional information
    # that we want to save when available.
    private class MessageWrap
      include JSON::Serializable

      getter message : Message
      getter usage : Usage?

      def initialize(@message, @usage); end
    end

    # The session itself is serializable so we can save a chat session
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    def initialize
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
  end
end
