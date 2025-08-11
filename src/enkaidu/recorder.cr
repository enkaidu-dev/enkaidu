module Enkaidu
  class Recorder
    FLUSH_AFTER = 10
    private getter rec_io : IO?
    private getter count_since_flush = 0

    def initialize(@rec_io = nil); end

    def <<(s)
      return unless io = rec_io
      io.puts s
      @count_since_flush += 1
      if count_since_flush >= FLUSH_AFTER
        flush
      end
    end

    def flush
      return unless io = rec_io
      io.flush
      @count_since_flush = 0
    end

    def close
      return unless io = rec_io
      io.close
    end
  end
end
