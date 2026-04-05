require "./event"

module Enkaidu::WUI::Render
  enum ContentType
    Text
    ImageUrl
  end

  class Query < Event
    getter content_type : ContentType
    getter content : String
    getter? via_query_queue : Bool

    def initialize(@content_type, @content, @via_query_queue = false)
      super("query")
    end
  end
end
