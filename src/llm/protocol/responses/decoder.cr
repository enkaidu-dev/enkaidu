require "json"

require "./inbound_stream_state"

require "../../events"
require "../../message/message"

module LLM::Protocol::Responses
  # Decodes the Responses wire (a streaming SSE event stream, or a single JSON
  # response object) onto the canonical `ChatEvent` vocabulary, and builds the
  # `Message::Response` (with its `Usage`) that production code appends to
  # history.
  #
  # The tool-call shape kept in the in-memory history is the ChatCompletions
  # wire form (the canonical model's historical representation); the events
  # yielded to the app are the canonical shapes.
  module Decoder
    # Parse a whole Responses event stream (SSE), yielding canonical events and
    # returning the aggregated `Message::Response`. Text/reasoning deltas are
    # concatenated into the response body; tool calls are finalized from
    # `output_item.added` / `function_call_arguments.*`; usage is captured (not
    # emitted) off `response.completed`, mirroring the ChatCompletions stream.
    private def prepare_message_from_streamed_data(stream_io, & : LLM::ChatEvent ->) : LLM::Message::Response
      state = InboundStreamState.new
      tool_calls = [] of JSON::Any
      content = ""

      reasoning = String.build do |think_io|
        content = String.build do |text_io|
          stream_io.each_line do |line|
            line = line.strip
            next if line.empty?

            # SSE frames pair a (non-JSON) `event:` field line with the
            # `data:` line that carries the JSON payload; only the latter
            # matters here (the event name is also in the payload's `type`),
            # so skip everything else (`event:`, `id:`, comments, …).
            next unless line.starts_with?("data:")

            payload = line.lchop("data:").lstrip
            if payload == "[DONE]"
              unless state.finished
                state.finished = true
                yield({type: LLM::Event::Done, content: JSON::Any.new(nil)})
              end
              next
            end

            begin
              data = JSON.parse(payload)
              handle_stream_event(data, state, text_io, think_io, tool_calls) do |event|
                yield event
              end
            rescue ex
              LLM.show_error_trace(ex, data_label: "line", data: line)
            end
          end

          # A stream can end with a tool call still in flight (no trailing
          # `...done` / `response.completed`). Finalize it so it still reaches
          # the yielded events and the history.
          state.finalize_all_tool_calls(tool_calls) do |event|
            yield event
          end
        end
      end

      msg = LLM::Message::Response.new(content, reasoning, tool_calls.empty? ? nil : tool_calls, state.reasoning_id, state.encrypted_content)
      msg.usage = state.usage if state.usage
      msg
    end

    # Map a single Responses event object to canonical events, mutating the
    # per-stream `state` / accumulation buffers as needed.
    # ameba:disable Metrics/CyclomaticComplexity: one branch per Responses event type; splitting would obscure the event mapping.
    private def handle_stream_event(data, state, text_io, think_io, tool_calls, & : LLM::ChatEvent ->) : Nil
      case dig_string(data, "type")
      when "response.output_text.delta", "response.output_text.done"
        if d = dig_string(data, "delta")
          text_io << d
          yield({type: LLM::Event::Text, content: JSON::Any.new(d)})
        end
      when "response.reasoning_summary_text.delta", "response.reasoning_summary_part.delta",
           "response.reasoning_text.delta", "response.reasoning_content.delta",
           "response.reasoning_part.delta", "response.reasoning.delta"
        if d = dig_string(data, "delta")
          think_io << d
          yield({type: LLM::Event::ReasoningEvent, content: JSON::Any.new(d)})
        end
      when "response.output_item.added"
        if item = data["item"]?
          case dig_string(item, "type")
          when "function_call"
            name = dig_string(item, "name") || ""
            id = dig_string(item, "call_id") || dig_string(item, "id") || ""
            args = dig_string(item, "arguments") || ""
            builder = FunctionCallBuilder.new(name, id, args)
            state.register_builder(data, builder)
            yield({type: LLM::Event::ReceivingToolCall, content: JSON::Any.new(name)})
          when "reasoning"
            state.reasoning_id ||= dig_string(item, "id")
            state.encrypted_content ||= dig_string(item, "encrypted_content")
          end
        end
      when "response.function_call_arguments.delta"
        if builder = state.find_builder(data)
          builder.append_args_json(dig_string(data, "delta"))
        end
      when "response.function_call_arguments.done", "response.output_item.done"
        if (item = data["item"]?) && (item_type = dig_string(item, "type"))
          if item_type == "reasoning"
            state.reasoning_id ||= dig_string(item, "id")
            state.encrypted_content ||= dig_string(item, "encrypted_content")
          end
          # Output item completion also covers messages and reasoning. Even a
          # matching index must not cause those items to finalize a tool call.
          return if dig_string(data, "type") == "response.output_item.done" && item_type != "function_call"
        end
        if builder = state.find_builder(data)
          # Complete arguments on a done event supersede accumulated deltas.
          if args = dig_string(data, "arguments")
            builder.replace_args_json(args)
          end
          if (item = data["item"]?) && dig_string(item, "type") == "function_call"
            if args = dig_string(item, "arguments")
              builder.replace_args_json(args)
            end
          end
          yield finalize_tool_call(builder, tool_calls)
          state.remove_builder(builder)
        end
      when "response.completed", "response.incomplete"
        # Finalize any in-flight tool call before the terminal event.
        state.finalize_all_tool_calls(tool_calls) do |event|
          yield event
        end
        if resp = data["response"]?
          if usage = extract_usage(resp)
            state.usage = usage
          end
          incomplete_reason = resp["incomplete_details"]? ? dig_string(resp["incomplete_details"], "reason") : nil
          finish = incomplete_reason || dig_string(resp, "status") || "incomplete"
          yield({type: LLM::Event::FinishReason, content: JSON::Any.new(finish)})
        else
          yield({type: LLM::Event::FinishReason, content: JSON::Any.new("incomplete")})
        end
        unless state.finished
          state.finished = true
          yield({type: LLM::Event::Done, content: JSON::Any.new(nil)})
        end
      when "response.failed", "error"
        yield({type: LLM::Event::ErrorServer, content: data})
      else
        # Unknown / ignorable event (`response.created`, `content_part.*`,
        # message/text done markers, …) — no canonical counterpart.
      end
    end

    # ameba:enable Metrics/CyclomaticComplexity

    # Close a tool call: record it in the CC-wire history and yield the
    # canonical `tool_call_requested` event. Returns the canonical event.
    private def finalize_tool_call(recent, tool_calls)
      recent.append_args_json(nil, complete: true)
      canonical = recent.to_function_call
      tool_calls << recent.to_cc_wire
      {type: LLM::Event::ToolCallRequested, content: canonical.json}
    end

    # Decode a non-streaming Responses body: walk `output[]` into canonical
    # events and produce the `Message::Response` (+ `Usage`).
    # ameba:disable Metrics/CyclomaticComplexity: one branch per output item type.
    private def process_responses_json(data : JSON::Any, & : LLM::ChatEvent ->) : LLM::Message::Response
      tool_calls = [] of JSON::Any
      content = nil.as String?
      reasoning = nil.as String?
      reasoning_id = nil.as String?
      encrypted_content = nil.as String?

      if out = data["output"]?.try(&.as_a)
        out.each do |item|
          case dig_string(item, "type")
          when "message"
            parts = [] of String
            if parts_json = item["content"]?.try(&.as_a)
              parts_json.each do |part|
                parts << (dig_string(part, "text") || "") if dig_string(part, "type") == "output_text"
              end
            end
            unless parts.empty?
              content = parts.join
              yield({type: LLM::Event::Text, content: JSON::Any.new(content)})
            end
          when "reasoning"
            reasoning_id ||= dig_string(item, "id")
            encrypted_content ||= dig_string(item, "encrypted_content")
            texts = [] of String
            if summary = item["summary"]?.try(&.as_a)
              summary.each do |part|
                texts << (dig_string(part, "text") || "") if dig_string(part, "type") == "summary_text"
              end
            end
            if content_parts = item["content"]?.try(&.as_a)
              content_parts.each do |part|
                part_type = dig_string(part, "type")
                if part_type == "reasoning_text" || part_type == "text" || part_type == "summary_text"
                  texts << (dig_string(part, "text") || "")
                end
              end
            elsif text = dig_string(item, "text")
              texts << text
            end
            unless texts.empty?
              joined = texts.join
              reasoning = joined
              yield({type: LLM::Event::ReasoningEvent, content: JSON::Any.new(joined)})
            end
          when "function_call"
            call = LLM::FunctionCall.new(
              dig_string(item, "call_id") || dig_string(item, "id") || "",
              dig_string(item, "name") || "",
              dig_string(item, "arguments") || "",
            )
            tool_calls << JSON.parse({
              "type"     => "function",
              "id"       => call.id,
              "function" => {
                "name"      => call.name,
                "arguments" => call.arguments,
              },
            }.to_json)
            yield({type: LLM::Event::ToolCallRequested, content: call.json})
          end
        end
      end

      usage = nil.as LLM::Usage?
      if u = data["usage"]?
        # Emit the raw Responses usage object as the event content (the app
        # layer treats it as a debug artifact, exactly as the CC decoder does).
        yield({type: LLM::Event::Usage, content: u})
        usage = LLM::Usage.from_responses(u)
      end
      incomplete_reason = data["incomplete_details"]? ? dig_string(data["incomplete_details"], "reason") : nil
      if finish = incomplete_reason || dig_string(data, "status")
        yield({type: LLM::Event::FinishReason, content: JSON::Any.new(finish)})
      end
      yield({type: LLM::Event::Done, content: JSON::Any.new(nil)})

      msg = LLM::Message::Response.new(content, reasoning, tool_calls.empty? ? nil : tool_calls, reasoning_id, encrypted_content)
      msg.usage = usage if usage
      msg
    end

    # ameba:enable Metrics/CyclomaticComplexity

    private def extract_usage(resp : JSON::Any?) : LLM::Usage?
      # `[]?` returns nil for a missing key; `dig` would raise `KeyError`.
      return unless resp
      u = resp["usage"]?
      return unless u
      LLM::Usage.from_responses(u)
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
