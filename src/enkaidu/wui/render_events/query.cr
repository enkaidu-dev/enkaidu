require "./event"

module Enkaidu::WUI::Render
  class Query < Event
    getter prompt : String

    def initialize(@prompt)
      super("query")
    end
  end
end
