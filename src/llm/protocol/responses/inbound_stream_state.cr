require "../../function_call"
require "../../usage"
require "./function_call_builder"

module LLM::Protocol::Responses
  # Mutable per-stream state: the in-flight tool calls and the usage captured
  # off `response.completed`. A class (reference type, not a struct/value
  # type) so field mutations made through the handler closure are seen by the
  # aggregator across the nested streaming closures.
  class InboundStreamState
    property? finished : Bool = false
    property? successful : Bool = false
    property? done_received : Bool = false
    property usage : LLM::Usage? = nil
    property reasoning_id : String? = nil
    property encrypted_content : String? = nil
    property responses_output : Array(JSON::Any)? = nil
    property? refusal : Bool = false
    property? refusal_text_received : Bool = false

    @completed_output_by_index = Hash(Int32, JSON::Any).new
    @completed_output_unindexed = [] of JSON::Any

    def record_output_item(data : JSON::Any) : Nil
      item = data["item"]?
      return unless item
      if index = data["output_index"]?.try(&.as_i?)
        @completed_output_by_index[index] = item
      else
        @completed_output_unindexed << item
      end
    end

    def finalize_responses_output(response : JSON::Any?) : Nil
      if output = response.try(&.["output"]?).try(&.as_a?)
        @responses_output = output
      elsif @completed_output_by_index.empty? && @completed_output_unindexed.size == 1
        @responses_output = @completed_output_unindexed
      elsif @completed_output_unindexed.empty?
        indexes = @completed_output_by_index.keys.sort!
        if indexes == (0...indexes.size).to_a
          @responses_output = indexes.map { |index| @completed_output_by_index[index] }
        end
      end
    end

    # Keep all builders, even those without identifiers, for EOF finalization.
    @builders = [] of FunctionCallBuilder
    @tool_builders = Hash(Int32 | String, FunctionCallBuilder).new
    @retired_keys = Set(Int32 | String).new

    def incomplete_builders? : Bool
      !@builders.empty?
    end

    def register_builder(data : JSON::Any, builder : FunctionCallBuilder) : Nil
      @builders << builder
      if idx = data["output_index"]?.try(&.as_i?)
        @retired_keys.delete(idx)
        @tool_builders[idx] = builder
      end
      if item = data["item"]?
        [dig_string(item, "call_id"), dig_string(item, "id")].each do |id|
          if id && !id.empty?
            @retired_keys.delete(id)
            @tool_builders[id] = builder
          end
        end
      end
    end

    def find_builder(data : JSON::Any) : FunctionCallBuilder?
      # Some providers omit identifiers. Only fall back when none were supplied
      # and exactly one call is in flight; an unknown identifier must never
      # redirect an event to an unrelated call.
      keys = [] of Int32 | String
      if idx = data["output_index"]?.try(&.as_i?)
        keys << idx
      end
      item = data["item"]?
      [dig_string(data, "call_id"), dig_string(data, "item_id"),
       dig_string(item, "call_id"), dig_string(item, "id")].each do |id|
        keys << id if id && !id.empty?
      end
      return @builders.first? if keys.empty? && @builders.size == 1
      return if keys.any? { |key| @retired_keys.includes?(key) }

      # Learn new aliases only when every known identifier agrees on one active
      # builder and no identifier is retired. Never learn from an ambiguous or
      # wholly unknown event, or overwrite another builder's association.
      matched = keys.compact_map { |key| @tool_builders[key]? }
      matched.uniq!
      return unless matched.size == 1

      builder = matched.first
      keys.each { |key| @tool_builders[key] = builder }
      builder
    end

    def remove_builder(builder : FunctionCallBuilder) : Nil
      @tool_builders.reject! do |key, b|
        if b == builder
          @retired_keys.add(key)
          true
        else
          false
        end
      end
      @builders.delete(builder)
    end

    def finalize_all_tool_calls(tool_calls, & : LLM::ChatEvent ->) : Nil
      @builders.each do |builder|
        unless builder.ready?
          builder.append_args_json(nil, complete: true)
          canonical = builder.to_function_call
          tool_calls << builder.to_cc_wire
          yield({type: LLM::Event::ToolCallRequested, content: canonical.json})
        end
      end
      @tool_builders.each_key { |key| @retired_keys.add(key) }
      @tool_builders.clear
      @builders.clear
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
