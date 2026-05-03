require "./event"

module Enkaidu::WUI::Render
  class SecurityConfirmation < Event
    getter description : String
    getter subjects : Array(String)
    getter id : String

    def initialize(@description, subject : String | Array(String), @id)
      @subjects = if subject.is_a?(String)
                    [subject]
                  else
                    subject
                  end
      super("security_confirmation")
    end
  end
end
