require "reply"

module Enkaidu::CLI
  # Command-line query reader with editing and other capabilities.
  class QueryReader < Reply::Reader
    def initialize(@input_history_file : String? = nil)
      super()
    end

    property prefix = "QUERY"

    def prompt(io : IO, line_number : Int32, color : Bool) : Nil
      q = "#{prefix} > "
      q = q.colorize(:yellow) if color

      io << q
    end

    # def highlight(expression : String) : String
    #   # Highlight the expression
    # end

    # def continue?(expression : String) : Bool
    #   # Return whether the interface should continue on multiline, depending of the expression
    # end

    # def format(expression : String) : String?
    #   # Reformat when expression is submitted
    # end

    # def indentation_level(expression_before_cursor : String) : Int32?
    #   # Compute the indentation from the expression
    # end

    def save_in_history?(expression : String) : Bool
      true
    end

    def history_file
      @input_history_file ||= ENV.fetch("ENKAIDU_HISTORY_FILE", ".enkaidu_history")
    end

    # def auto_complete(name_filter : String, expression : String) : {String, Array(String)}
    #   # Return the auto-completion result from expression
    # end
  end
end
