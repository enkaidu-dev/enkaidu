require "../param"

module LLM::OpenAI
  # Defines a function (tool) call, with ability to build up the
  # args from chunks when streaming. USED AS AN INTERIM object; maybe one day
  # the whole system won't be hung on JSON::Any scaffolding.
  private class FunctionCall
    getter name : String
    getter id : String
    getter args_json : String
    getter? ready

    def initialize(@name, @id, @args_json = "", @ready = false); end

    def append_args_json(args_part : String?, complete = false)
      return if ready?
      if args_part
        @args_json = @args_json + args_part
      end
      @ready = true if complete
    end
  end
end
