require "./event"

module Enkaidu::WUI::Render
  enum ContentType
    Text
    ImageUrl
  end

  class Query < Event
    getter content_type : ContentType
    getter content : String
    getter? via_macro : Bool

    def initialize(@content_type, @content, @via_macro = false)
      super("query")
    end
  end
end
