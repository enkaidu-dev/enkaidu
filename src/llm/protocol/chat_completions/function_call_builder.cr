module LLM::Protocol::ChatCompletions
  # Accumulates a (possibly streaming) Chat-Completions tool call. Protocol-
  # specific: it retains `extra_content` for dialect tolerance and knows the
  # CC wire layout. Distinct from the canonical core `LLM::FunctionCall`,
  # which is built from it (via id/name/args_json) when complete.
  private class FunctionCallBuilder
    getter name : String
    getter id : String
    getter args_json : String
    getter? ready
    getter extra_content : JSON::Any?

    def initialize(@name, @id, @args_json = "", @ready = false, @extra_content = nil); end

    def append_args_json(args_part : String?, complete = false)
      return if ready?
      if args_part
        @args_json = @args_json + args_part
      end
      @ready = true if complete
    end
  end
end
