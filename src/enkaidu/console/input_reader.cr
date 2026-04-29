require "reply"
require "colorize"

module Enkaidu::Console
  class InputReader < Reply::Reader
    property label : String

    def initialize(@label)
      super()
    end

    def prompt(io : IO, line_number : Int32, color : Bool) : Nil
      q = label.colorize(:cyan) if color
      io << q
    end
  end
end
