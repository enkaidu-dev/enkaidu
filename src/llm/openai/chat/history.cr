require "json"

require "./message"
require "./usage"

module LLM::OpenAI
  # The serializable chat history keeps all wrapped messages to save
  # the additional information when saving the session.
  class History
    # This wrapper is used to keep the `Message` and additional information
    # that we want to save when available.
    class MessageWrap
      include JSON::Serializable

      getter message : Message
      getter usage : Usage?

      def initialize(@message, @usage); end
    end

    # The history itself is serializable so we can save a chat's history
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    getter format : String

    def initialize
      @format = self.class.name
      @messages = [] of MessageWrap
    end

    def branch(from : History)
      @messages = from.@messages.dup
    end

    def append_message(msg : Message, usage : Usage? = nil)
      @messages << MessageWrap.new(msg, usage)
    end

    # This yields each `Message` in the history
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

    private def tail_chat_messages(num = 1, &)
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

      @messages.each(start: start_index, count: @messages.size - start_index) do |msgplus|
        yield msgplus
      end
    end

    def transfer_tail_chats(to : History, num = 1, filter_by_role : String? = nil)
      tail_chat_messages(num) do |msgplus|
        msg = msgplus.message
        to.append_message(msg, msgplus.usage) if filter_by_role.nil? || filter_by_role == msg.role
      end
    end

    # Emit the last N request responses. Always tries to emit the query before the response. May include
    # tool calls as a result. Use N=-1 to list all
    def tail_chats(num = -1, & : ChatEvent ->)
      tail_chat_messages(num) do |msgplus|
        msgplus.message.emit { |chat_ev| yield chat_ev }
      end
    end

    private def convert_for_user(content : MCP::Content) : Message::MultiContent
      case content
      when MCP::Content::Text
        Message::MultiContent.new(content.text)
      when MCP::Content::Image
        mc = Message::MultiContent.new
        mc.image_url "data:#{content.mime_type};base64,#{content.data}"
        mc
      else
        raise UnexpectedMCPPrompt.new("Unexpected MCP prompt \"user\" message content: #{content.to_json}")
      end
    end

    private def convert_for_asst(content : MCP::Content) : Message::Response
      case content
      when MCP::Content::Text
        Message::Response.new(content: content.text, reasoning: nil)
      else
        raise UnexpectedMCPPrompt.new("Unexpected MCP prompt \"assistant\" message content: #{content.to_json}")
      end
    end

    def import(prompt : MCP::PromptResult, emit = false, & : ChatEvent ->) : Nil
      prompt.each do |prompt_msg|
        msg = case prompt_msg.role
              when MCP::Role::Assistant
                convert_for_asst(prompt_msg.content)
              when MCP::Role::User
                convert_for_user(prompt_msg.content)
              end
        if msg.nil?
          STDERR.puts "~~~ WTF: prompt: #{prompt.to_json}"
        else
          append_message(msg)
          msg.emit { |event| yield event } if emit
        end
      end
    end
  end
end
