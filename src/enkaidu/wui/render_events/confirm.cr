require "./event"

module Enkaidu::WUI::Render
  class SecurityConfirmation < Event
    getter banner : NamedTuple(safe: Bool, message: String)?
    getter description : String
    getter subjects : Array(String)
    getter id : String

    def initialize(@description, subject : String | Array(String), @id, @banner = nil)
      @subjects = if subject.is_a?(String)
                    [subject]
                  else
                    subject
                  end
      super("security_confirmation")
    end
  end
end
