require "reply"

module Enkaidu::CLI
  # Command-line query reader with editing and other capabilities.
  class QueryReader < Reply::Reader
    # Incicators is an array of strings that are presented as a prefix
    # to the input prompt.
    property indicators : Array(String)? = nil

    def initialize(@input_history_file : String? = nil)
      super()
    end

    def read_next
      puts
      super
    end

    def prompt(io : IO, line_number : Int32, color : Bool) : Nil
      q = if (tags = indicators) && tags.present?
            prefix = tags.join('|')
            "[#{prefix}] QUERY > "
          else
            "QUERY > "
          end
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
