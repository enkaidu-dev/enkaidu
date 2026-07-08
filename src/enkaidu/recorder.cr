module Enkaidu
  # Recorder class handles recording in-app events and debug events for troubleshooting LLM comms
  class Recorder
    private getter rec_io : IO?

    # Initializes a new Recorder instance with an optional IO object for recording.
    def initialize(@rec_io = nil); end

    # Appends a string to the rec_io. Flushes if threshold is reached.
    def <<(s)
      if_recording? do |io|
        io.puts(s)
      end
    end

    # Yield with `IO` to write to if recording
    def if_recording?(& : IO ->)
      return unless io = rec_io

      yield io
      flush
    end

    # Flushes the rec_io.
    def flush
      return unless io = rec_io
      io.flush
    end

    # Closes the rec_io.
    def close
      return unless io = rec_io
      io.close
    end
  end
end
