require "./event"

module Enkaidu::WUI::Render
  class SessionReset < Event
    def initialize
      super "session_reset"
    end
  end
end
