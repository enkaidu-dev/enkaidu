require "./event"

module Enkaidu::WUI::Render
  enum ContentType
    Text
    ImageUrl
  end

  class Query < Event
    getter content_type : ContentType
    getter content : String

    def initialize(@content_type, @content)
      super("query")
    end
  end
end
