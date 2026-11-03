require "../../function_call"
require "../../usage"
require "./function_call_builder"

module LLM::Protocol::Responses
  # Mutable per-stream state: the in-flight tool call and the usage captured
  # off `response.completed`. A class (reference type, not a struct/value
  # type) so field mutations made through the handler closure are seen by the
  # aggregator across the nested streaming closures.
  class InboundStreamState
    # ameba:disable Naming/QueryBoolMethods
    property finished : Bool = false
    property usage : LLM::Usage? = nil
    property reasoning_id : String? = nil
    property encrypted_content : String? = nil
    # ameba:enable Naming/QueryBoolMethods

    # In-flight tool call builders keyed by output_index or call_id
    getter tool_builders = Hash(Int32 | String, FunctionCallBuilder).new
    property recent_builder : FunctionCallBuilder? = nil

    def register_builder(data : JSON::Any, builder : FunctionCallBuilder) : Nil
      if idx = data["output_index"]?.try(&.as_i?)
        @tool_builders[idx] = builder
      end
      if (item = data["item"]?) && (call_id = dig_string(item, "call_id") || dig_string(item, "id"))
        @tool_builders[call_id] = builder
      end
      unless builder.id.empty?
        @tool_builders[builder.id] = builder
      end
      @recent_builder = builder
    end

    def find_builder(data : JSON::Any) : FunctionCallBuilder?
      if idx = data["output_index"]?.try(&.as_i?)
        if b = @tool_builders[idx]?
          return b
        end
      end
      if id = dig_string(data, "call_id") || dig_string(data, "item_id")
        if b = @tool_builders[id]?
          return b
        end
      end
      if (item = data["item"]?) && (id = dig_string(item, "call_id") || dig_string(item, "id"))
        if b = @tool_builders[id]?
          return b
        end
      end
      @recent_builder
    end

    def remove_builder(builder : FunctionCallBuilder) : Nil
      @tool_builders.reject! { |_, b| b == builder }
      @recent_builder = nil if @recent_builder == builder
    end

    def finalize_all_tool_calls(tool_calls, & : LLM::ChatEvent ->) : Nil
      builders = @tool_builders.values
      if recent = @recent_builder
        builders << recent
      end
      builders.uniq!
      builders.each do |builder|
        unless builder.ready?
          builder.append_args_json(nil, complete: true)
          canonical = builder.to_function_call
          tool_calls << builder.to_cc_wire
          yield({type: LLM::Event::ToolCallRequested, content: canonical.json})
        end
      end
      @tool_builders.clear
      @recent_builder = nil
    end

    private def dig_string(json, key) : String?
      return unless json
      hash = json.as_h?
      return unless hash
      raw = hash[key]?.try(&.raw)
      raw.is_a?(String) ? raw : nil
    end
  end
end
