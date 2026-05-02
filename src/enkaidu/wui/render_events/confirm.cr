require "./event"

module Enkaidu::WUI::Render
  class SecurityConfirmation < Event
    getter description : String
    getter subject : String
    getter id : String

    def initialize(@description, @subject, @id)
      super("security_confirmation")
    end
  end
end
