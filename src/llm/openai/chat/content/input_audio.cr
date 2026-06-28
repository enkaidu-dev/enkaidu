require "../content.cr"

module LLM::OpenAI
  # Represents file `content` within a message to the LLM
  class Content::InputAudio < Content
    property input_audio = {} of String => String

    def initialize(base64_data : String, format : String)
      @type = "input_audio"
      @input_audio["data"] = base64_data
      @input_audio["format"] = format
    end

    # Emit this content as one or more `ChatEvent` objects
    def emit(& : ChatEvent ->) : Nil
      yield({type: "query/input_audio", content: JSON::Any.new(input_audio["format"])})
    end
  end
end
