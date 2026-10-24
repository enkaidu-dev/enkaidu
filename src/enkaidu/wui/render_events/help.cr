require "./event"

module Enkaidu::WUI::Render
  class HelpResponse < Event
    include JSON::Serializable

    property title : String
    property body : String

    def initialize(@title, @body)
      super("help_response")
    end
  end
end
