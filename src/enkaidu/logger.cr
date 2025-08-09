module Enkaidu
  class Logger
    private getter io : IO?

    def initialize(@io = nil)
    end

    def log(s)
      return unless log_io = io
      log_io.puts s
    end

    def log_close
      return unless log_io = io
      log_io.close
    end
  end
end
