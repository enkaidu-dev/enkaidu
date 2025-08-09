module Enkaidu
  class Logger
    private getter io : IO?

    def initialize(@io = nil)
    end

    def log(s)
      if (log_io = io)
        log_io.puts s
      end
    end

    def log_close
      if (log_io = io)
        log_io.close
      end
    end
  end
end
