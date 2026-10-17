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

  # Emitted once, when the runtime finishes (/bye) and the WUI server is about
  # to shut down.  The web UI uses this as the unambiguous "session is over"
  # signal so it can lock the prompt bar and tell the user they may close the tab.
  class SessionShutdown < Event
    def initialize
      super "session_shutdown"
    end
  end
end
