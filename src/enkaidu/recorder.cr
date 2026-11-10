module Enkaidu
  # Recorder class handles recording in-app events and debug events for troubleshooting LLM comms
  #
  # The recorder is a *debug artifact only* — not a contract. It writes the
  # raw `ChatEvent` payloads verbatim, so their shape can (and does) change
  # without backward-compatibility guarantees. In particular, the LLM Phase 1
  # reorg (canonical tool-call boundary type) changed the recorded payloads
  # for `tool_call_requested` / `calling_tool` / `error/unknown_tool_call`
  # (now `{id, name, arguments}`) and `tool_call/done` (now `{id, name, output}`),
  # dropping the CC-wire `{type, function: {name, arguments}}` shape. Recordings
  # made before that change are therefore not directly comparable to later ones.
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
