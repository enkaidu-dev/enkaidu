require "./event"

module Enkaidu::WUI::Render
  class SessionInfo < Event
    getter id : String
    getter model : String
    getter? readonly : Bool

    def initialize(session)
      super "session_info"
      @id = session.id
      @model = session.chat.model || "unknown"
      @readonly = session.readonly?
    end
  end

  class SessionReset < Event
    def initialize
      super "session_reset"
    end
  end
end
