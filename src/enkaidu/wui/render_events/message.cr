require "./event"

module Enkaidu::WUI::Render
  abstract class Message < Event
    use_json_discriminator "level", {
      info: InfoMessage, warn: WarningMessage, error: ErrorMessage,
      success: SuccessMessage,
    }

    getter level : String
    getter message : String
    getter? markdown : Bool
    getter details : String?

    def initialize(@level, @message, @details, @markdown)
      super("message")
    end
  end

  class InfoMessage < Message
    def initialize(message, details = nil, markdown = false)
      super("info", message, details, markdown)
    end
  end

  class WarningMessage < Message
    def initialize(@message, @details = nil, @markdown = false)
      super("warn", message, details, markdown)
    end
  end

  class ErrorMessage < Message
    def initialize(@message, @details = nil, @markdown = false)
      super("error", message, details, markdown)
    end
  end

  class SuccessMessage < Message
    def initialize(@message, @details = nil, @markdown = false)
      super("success", message, details, markdown)
    end
  end
end
