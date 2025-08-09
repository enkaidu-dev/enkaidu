require "option_parser"

module Enkaidu
  module Helpers
    def warning(message)
      STDERR.puts "***".colorize(:red)
      STDERR.puts message.colorize(:red)
      STDERR.puts
    end

    def error_with(message, help = nil)
      STDERR.puts message.colorize(:red)
      if help
        STDERR.puts
        STDERR.puts help
      end
      exit(1)
    end
  end

end
