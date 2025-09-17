require "../message"

module LLM::OpenAI
  # Represents a multi-content message in a request to the LLM
  class Message::MultiContent < Message
    include JSON::Serializable

    property content = [] of Content

    def initialize(prompt : String, attach : Chat::Inclusions? = nil)
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

    private def text(text : String)
      content << Content::Text.new(text)
    end

    private def image_url(url : String)
      content << Content::ImageUrl.new(url)
    end

    private def file_data(base64_data : String, file_name : String)
      content << Content::FileData.new(base64_data: base64_data, file_name: file_name)
    end
  end
end
