require "../message"

module LLM::OpenAI
  # Represents a multi-content message in a request to the LLM
  class Message::MultiContent < Message
    ROLE = "user"

    property content = [] of Content

    def initialize(prompt : String, attach : ChatInclusions? = nil)
      @role = "user"
      text(prompt)
      if more = attach
        more.each do |inclusion|
          case inclusion[:type]
          when .text?       then text(inclusion[:data])
          when .image_data? then image_url(inclusion[:data])
          when .file_data?  then file_data(inclusion[:data], inclusion[:name])
          when .audio_data? then input_audio(inclusion[:data], inclusion[:format] || "unknown")
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

    protected def input_audio(base64_data : String, format : String)
      content << Content::InputAudio.new(base64_data: base64_data, format: format)
    end

    # Emit this message as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      content.each do |content|
        content.emit do |chat_ev|
          yield chat_ev
        end
      end
    end

    protected def protocol_fields_to_json(json : JSON::Builder)
      super
      json.field "content" do
        json.array do
          content.each do |item|
            item.to_json(json)
          end
        end
      end
    end
  end
end
