require "../content"

# Monkey-patch to support JSON conversion
struct MIME::MediaType
  def self.from_json(pull : JSON::PullParser)
    self.parse(pull.read_string)
  end

  def self.to_json(value, jsonb : JSON::Builder)
    jsonb.string value.media_type
  end

  def to_json(io)
    media_type.to_json(io)
  end
end

module MCPC
  abstract class Content::Media < Content
    private MIME_TYPE_KEY = "mimeType"

    getter data : String

    @[JSON::Field(key = MIME_TYPE_KEY)]
    getter mime_type : MIME::MediaType

    def initialize(type, @data, @mime_type)
      super type
    end

    def self.import(json : JSON::Any)
      if (mime = json[MIME_TYPE_KEY].as_s) && (media_type = MIME::MediaType.parse?(mime))
        self.new(
          json["data"].as_s,
          media_type)
      else
        raise InvalidContentProperty.new("Imvalid media type: #{mime || "nil"}")
      end
    end
  end
end
