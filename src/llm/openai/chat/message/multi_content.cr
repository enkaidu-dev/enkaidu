require "../message"

module LLM::OpenAI
  # Represents a multi-content message in a request to the LLM
  class Message::MultiContent < Message
    property content = [] of Content

    def initialize(prompt : String, attach : ChatInclusions? = nil)
      @role = "user"
      text(prompt)
      if more = attach
        more.each do |content|
          case content[:type]
          when .text?       then text(content[:data])
          when .image_data? then image_url(content[:data])
          when .file_data?  then file_data(content[:data], content[:name])
          end
        end
      end
    end

    protected def initialize
      @role = "user"
    end

    protected def text(text : String)
      content << Content::Text.new(text)
    end

    protected def image_url(url : String)
      content << Content::ImageUrl.new(url)
    end

    protected def file_data(base64_data : String, file_name : String)
      content << Content::FileData.new(base64_data: base64_data, file_name: file_name)
    end

    # Emit this message as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      content.each do |content|
        content.emit do |chat_ev|
          yield chat_ev
        end
      end
    end
  end
end
