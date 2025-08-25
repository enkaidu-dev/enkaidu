module Enkaidu
  # Recorder class handles recording in-app events and debug events for troubleshooting LLM comms
  class Recorder
    FLUSH_AFTER = 10
    private getter rec_io : IO?
    private getter count_since_flush = 0

    # Initializes a new Recorder instance with an optional IO object for recording.
    def initialize(@rec_io = nil); end

    # Appends a string to the rec_io. Flushes if threshold is reached.
    def <<(s)
      return unless io = rec_io
      io.puts s
      @count_since_flush += 1
      return unless count_since_flush >= FLUSH_AFTER
      flush
    end

    # Flushes the rec_io.
    def flush
      return unless io = rec_io
      io.flush
      @count_since_flush = 0
    end

    # Closes the rec_io.
    def close
      return unless io = rec_io
      io.close
    end
  end
end
