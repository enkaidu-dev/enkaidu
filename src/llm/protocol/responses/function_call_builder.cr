require "../../function_call"

module LLM::Protocol::Responses
  # Accumulates a (possibly streaming) Responses-API tool call. Protocol-
  # specific: it keys off the Responses wire event layout
  # (`output_item.added` seeds it, `function_call_arguments.delta` appends,
  # `...done` finalizes). Distinct from the canonical core `LLM::FunctionCall`,
  # which it produces when complete, and from the ChatCompletions-wire form
  # the canonical history keeps.
  private class FunctionCallBuilder
    getter name : String
    getter id : String
    getter args_json : String
    getter? ready

    def initialize(@name, @id, @args_json = "", @ready = false); end

    def append_args_json(args_part : String?, complete = false)
      return if ready?
      @args_json = @args_json + args_part if args_part
      @ready = true if complete
    end

    # Replace the accumulated arguments wholesale (used when a later event
    # carries the complete argument string and no incremental deltas were seen).
    def replace_args_json(args : String?) : Nil
      return if ready? || args.nil? || args.blank?
      @args_json = args
    end

    # The canonical, closed `LLM::FunctionCall` this builder has accumulated.
    def to_function_call : LLM::FunctionCall
      LLM::FunctionCall.new(id, name, args_json)
    end

    # The ChatCompletions-wire representation the canonical history stores for
    # a tool call: `{type, id, function:{name, arguments, ...}}`.
    def to_cc_wire : JSON::Any
      JSON.parse({
        "type"     => "function",
        "id"       => id,
        "function" => {
          "name"      => name,
          "arguments" => args_json,
        },
      }.to_json)
    end
  end
end
