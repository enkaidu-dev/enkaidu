require "./event"

module Enkaidu::WUI::Render
  class ShellConfirmation < Event
    getter command : String
    getter id : String

    def initialize(@command, @id)
      super("shell_confirmation")
    end
  end
end
