require "../../spec_helper"
require "json"
require "io/memory"

# Unit tests for the Responses-protocol streaming parser
# (`LLM::Protocol::Responses::Decoder#prepare_message_from_streamed_data`), i.e.
# the SSE event mapping and tool-call accumulation
#
# These drive the parser directly with hand-built Responses event streams — no
# HTTP, no Wiretap transcript, no live backend — so they pin the wire-shape
# interpretation of the Responses event vocabulary: `output_text.delta`,
# `reasoning_summary_text.delta`, the `output_item.added` /
# `function_call_arguments.{delta,done}` lifecycle, and `response.completed`
# (usage + status). Construction is offline (the endpoint/key resolve lazily on
# `#post_and_stream`, which this spec does not invoke).
#
# The parser is private on the `Responses::Chat`; a thin test subclass exposes
# it, the same trick `cc_streaming_parse_spec.cr` uses.
#
# NOTE: every helper here is prefixed `rsp_` and uniquely named on purpose.
# Spectator compiles every spec file into one program, so a top-level helper
# that shares a name *and signature* with another spec (e.g. `cc_streaming_
# parse_spec.cr` also defines `delta_text`/`usage_obj`/`events_of`) would leak
# into that spec and cross-contaminate it.
class ResponsesParseTestChat < LLM::Protocol::Responses::Chat
  # Parse one whole SSE body; returns the yielded canonical events plus the
  # aggregated `Message::Response` production code would append to history.
  def parse_streamed(sse_body : String) : {Array(LLM::ChatEvent), LLM::Message::Response}
    events = [] of LLM::ChatEvent
    io = IO::Memory.new(sse_body)
    msg = prepare_message_from_streamed_data(io) do |ev|
      events << ev
    end
    {events, msg.not_nil!}
  end
end

def rsp_build_parse_chat : ResponsesParseTestChat
  ResponsesParseTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
end

def rsp_events_of(events, type : LLM::Event) : Array(LLM::ChatEvent)
  events.select { |e| e["type"] == type }
end

# --- Fixtures -------------------------------------------------------------
# Each builder returns the JSON *text* of one Responses event; `rsp_sse_body`
# frames them as `data:` event-stream lines and optionally appends `[DONE]`.

def rsp_delta_text(text : String) : String
  JSON.build do |j|
    j.object do
      j.field "type", "response.output_text.delta"
      j.field "delta", text
    end
  end
end

def rsp_delta_reasoning(text : String) : String
  JSON.build do |j|
    j.object do
      j.field "type", "response.reasoning_summary_text.delta"
      j.field "delta", text
    end
  end
end

# A `response.output_item.added` for a function call, with its initial arguments
# (empty unless the server pre-fills them — as Ollama's single-chunk style does).
def rsp_added_function_call(item_id : String, name : String, arguments = "", output_index : Int32? = nil, wire_id : String? = nil) : String
  JSON.build do |j|
    j.object do
      j.field "type", "response.output_item.added"
      j.field "output_index", output_index if output_index
      j.field "item" do
        j.object do
          j.field "type", "function_call"
          j.field "call_id", item_id
          j.field "id", wire_id if wire_id
          j.field "name", name
          j.field "arguments", arguments
        end
      end
    end
  end
end

def rsp_args_delta(fragment : String, item_id : String? = nil, output_index : Int32? = nil) : String
  JSON.build do |j|
    j.object do
      j.field "type", "response.function_call_arguments.delta"
      j.field "item_id", item_id if item_id
      j.field "output_index", output_index if output_index
      j.field "delta", fragment
    end
  end
end

def rsp_args_done(item_id : String, output_index : Int32? = nil) : String
  JSON.build do |j|
    j.object do
      j.field "type", "response.function_call_arguments.done"
      j.field "item_id", item_id
      j.field "output_index", output_index if output_index
    end
  end
end

# The terminal event carrying usage. `usage` is the Responses usage object
# (`input_tokens`/`output_tokens`/`total_tokens`).
def rsp_completed(status = "completed", usage = nil.as(JSON::Any?)) : String
  JSON.build do |json|
    json.object do
      json.field "type", "response.completed"
      json.field "response" do
        json.object do
          json.field "status", status
          json.field "usage", usage if usage
        end
      end
    end
  end
end

# The whole SSE body from a list of event payloads, optionally with `[DONE]`.
def rsp_sse_body(payloads : Array(String), done : Bool = true) : String
  out = String.build do |io|
    payloads.each { |p| io << "data: " << p << "\n\n" }
    io << "data: [DONE]\n\n" if done
  end
  out
end

# A Responses usage object as JSON::Any.
def rsp_usage_obj(prompt : Int32, completion : Int32, total : Int32) : JSON::Any
  JSON.parse(JSON.build do |j|
    j.object do
      j.field "input_tokens", prompt
      j.field "output_tokens", completion
      j.field "total_tokens", total
    end
  end)
end

Spectator.describe "LLM::Protocol::Responses streaming parse" do
  describe "#prepare_message_from_streamed_data (streaming aggregation)" do
    it "assembles text deltas and captures usage off the completed event" do
      chat = rsp_build_parse_chat
      body = rsp_sse_body [
        rsp_delta_text("Hello"),
        rsp_delta_text(" world"),
        rsp_completed("completed", rsp_usage_obj(7, 5, 12)),
      ]
      events, msg = chat.parse_streamed(body)

      expect(rsp_events_of(events, LLM::Event::Text).map { |e| e["content"].as_s }).to eq(["Hello", " world"])
      expect(msg.content).to eq("Hello world")

      # The terminal `response.completed` emits a finish reason and a done.
      expect(rsp_events_of(events, LLM::Event::FinishReason).first["content"].as_s).to eq("completed")
      expect(rsp_events_of(events, LLM::Event::Done).size).to eq(1)

      # Streaming captures usage onto the response rather than emitting an event.
      expect(rsp_events_of(events, LLM::Event::Usage).size).to eq(0)
      expect(msg.usage.not_nil!.total_tokens).to eq(12)
      expect(msg.usage.not_nil!.prompt_tokens).to eq(7)
      expect(msg.usage.not_nil!.completion_tokens).to eq(5)
    end

    it "assembles a tool call whose arguments arrive across multiple delta events" do
      chat = rsp_build_parse_chat
      body = rsp_sse_body [
        rsp_added_function_call("call_abc", "echo", ""), # start
        rsp_args_delta(%q|{"value": |),                  # merge
        rsp_args_delta(%q|"hello"}|),                    # merge
        rsp_args_done("call_abc"),
        rsp_completed,
      ]
      events, msg = chat.parse_streamed(body)

      # `receiving_tool_call` names one tool; `tool_call_requested` is the
      # canonical closed call, emitted exactly once.
      expect(rsp_events_of(events, LLM::Event::ReceivingToolCall).size).to eq(1)
      expect(rsp_events_of(events, LLM::Event::ReceivingToolCall).first["content"].as_s).to eq("echo")
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested)
      expect(reqs.size).to eq(1)
      req = reqs.first["content"]
      expect(req.dig("id").as_s).to eq("call_abc")
      expect(req.dig("name").as_s).to eq("echo")
      expect(req.dig("arguments").as_s).to eq(%q|{"value": "hello"}|)

      # History keeps the ChatCompletions-wire shape; the assembled arguments
      # round-trip through it.
      wire = msg.tool_calls.not_nil!
      expect(wire.size).to eq(1)
      expect(wire.first.dig("function", "name").as_s).to eq("echo")
      expect(wire.first.dig("function", "arguments").as_s).to eq(%q|{"value": "hello"}|)
      expect(wire.first.as_h.has_key?("function")).to eq(true)
    end

    it "captures reasoning summary deltas onto the response" do
      chat = rsp_build_parse_chat
      body = rsp_sse_body [
        rsp_delta_reasoning("th"),
        rsp_delta_reasoning("ink"),
        rsp_delta_text("hi"),
        rsp_completed,
      ]
      events, msg = chat.parse_streamed(body)

      expect(rsp_events_of(events, LLM::Event::ReasoningEvent).map { |e| e["content"].as_s }).to eq(["th", "ink"])
      expect(msg.reasoning).to eq("think")
      expect(msg.content).to eq("hi")
    end

    it "recovers from a malformed data line and continues the stream" do
      chat = rsp_build_parse_chat
      body = rsp_sse_body [
        rsp_delta_text("hi"),
        "this is not valid json", # malformed payload -> per-line rescue, keep going
        rsp_delta_text(" there"),
        rsp_completed,
      ]
      events, msg = chat.parse_streamed(body)

      expect(rsp_events_of(events, LLM::Event::Text).map { |e| e["content"].as_s }).to eq(["hi", " there"])
      expect(msg.content).to eq("hi there")
    end

    it "assembles interleaved parallel tool calls keyed by output_index" do
      chat = rsp_build_parse_chat
      body = rsp_sse_body [
        rsp_added_function_call("call_1", "echo", "", output_index: 0),
        rsp_added_function_call("call_2", "read", "", output_index: 1),
        rsp_args_delta(%q|{"val": |, output_index: 0),
        rsp_args_delta(%q|{"path": |, output_index: 1),
        rsp_args_delta(%q|"first"}|, output_index: 0),
        rsp_args_delta(%q|"file.txt"}|, output_index: 1),
        rsp_args_done("call_1", output_index: 0),
        rsp_args_done("call_2", output_index: 1),
        rsp_completed,
      ]
      events, msg = chat.parse_streamed(body)

      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested)
      expect(reqs.size).to eq(2)
      expect(reqs[0]["content"].dig("name").as_s).to eq("echo")
      expect(reqs[0]["content"].dig("arguments").as_s).to eq(%q|{"val": "first"}|)
      expect(reqs[1]["content"].dig("name").as_s).to eq("read")
      expect(reqs[1]["content"].dig("arguments").as_s).to eq(%q|{"path": "file.txt"}|)

      wire = msg.tool_calls.not_nil!
      expect(wire.size).to eq(2)
      expect(wire[0].dig("function", "arguments").as_s).to eq(%q|{"val": "first"}|)
      expect(wire[1].dig("function", "arguments").as_s).to eq(%q|{"path": "file.txt"}|)
    end

    it "keeps parallel calls separate across both kinds of done events" do
      body = rsp_sse_body [
        rsp_added_function_call("call_a", "echo", output_index: 0, wire_id: "item_a"),
        rsp_added_function_call("call_b", "read", output_index: 1, wire_id: "item_b"),
        rsp_args_delta(%q|{"value":|, item_id: "item_a"),
        rsp_args_delta(%q|{"path":|, item_id: "item_b"),
        rsp_args_delta(%q|"hello"}|, item_id: "item_a"),
        %q|{"type":"response.function_call_arguments.done","item_id":"item_a","arguments":"{\"value\":\"hello\"}"}|,
        %q|{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"item_a","call_id":"call_a","arguments":"{\"value\":\"hello\"}"}}|,
        %q|{"type":"response.output_item.done","output_index":1,"item":{"type":"reasoning","id":"reasoning_x","encrypted_content":"secret"}}|,
        %q|{"type":"response.output_item.done","item":{"type":"message","id":"msg_x"}}|,
        rsp_args_delta(%q|"file.txt"}|, item_id: "item_b"),
        rsp_args_done("item_b"),
        rsp_completed,
      ]
      events, msg = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested).map { |e| e["content"] }
      expect(reqs.size).to eq(2)
      expect(reqs.map { |r| [r["id"].as_s, r["name"].as_s, r["arguments"].as_s] }).to eq([
        ["call_a", "echo", %q|{"value":"hello"}|],
        ["call_b", "read", %q|{"path":"file.txt"}|],
      ])
      wire = msg.tool_calls.not_nil!
      expect(wire.map { |c| [c["id"].as_s, c.dig("function", "arguments").as_s] }).to eq([
        ["call_a", %q|{"value":"hello"}|],
        ["call_b", %q|{"path":"file.txt"}|],
      ])
      expect(msg.reasoning_id).to eq("reasoning_x")
      expect(msg.encrypted_content).to eq("secret")
    end

    it "ignores unknown identified events instead of assigning them to the latest call" do
      body = rsp_sse_body [
        rsp_added_function_call("call_a", "echo", wire_id: "item_a"),
        rsp_added_function_call("call_b", "read", wire_id: "item_b"),
        rsp_args_delta("wrong", item_id: "unknown"),
        rsp_args_done("unknown"),
        rsp_args_delta("wrong", output_index: 99),
        rsp_args_delta("A", item_id: "item_a"),
        rsp_args_delta("B", item_id: "item_b"),
        rsp_args_done("item_a"),
        rsp_args_done("item_b"),
        rsp_completed,
      ]
      events, msg = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested).map { |e| e["content"] }
      expect(reqs.map { |r| [r["id"].as_s, r["arguments"].as_s] }).to eq([["call_a", "A"], ["call_b", "B"]])
      expect(msg.tool_calls.not_nil!.map { |c| c.dig("function", "arguments").as_s }).to eq(["A", "B"])
    end

    it "rejects conflicting or retired identifiers without assigning another call" do
      body = rsp_sse_body [
        rsp_added_function_call("call_a", "echo", output_index: 0, wire_id: "item_a"),
        rsp_added_function_call("call_b", "read", output_index: 1, wire_id: "item_b"),
        rsp_args_delta("wrong", item_id: "item_a", output_index: 1),
        rsp_args_delta("A", item_id: "item_a"),
        rsp_args_done("item_a"),
        %q|{"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","id":"item_a","call_id":"call_a","arguments":"wrong"}}|,
        rsp_args_delta("B", item_id: "item_b"),
        rsp_args_done("item_b"),
        rsp_completed,
      ]
      events, _ = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested).map { |e| e["content"] }
      expect(reqs.map { |r| [r["id"].as_s, r["arguments"].as_s] }).to eq([["call_a", "A"], ["call_b", "B"]])
    end

    it "accepts unkeyed single-call events and function item completion" do
      body = rsp_sse_body [
        rsp_added_function_call("call_one", "echo"),
        rsp_args_delta("partial"),
        %q|{"type":"response.output_item.done","item":{"type":"function_call","arguments":"complete"}}|,
        rsp_completed,
      ]
      events, msg = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested)
      expect(reqs.size).to eq(1)
      expect(reqs.first["content"]["arguments"].as_s).to eq("complete")
      expect(msg.tool_calls.not_nil!.first.dig("function", "arguments").as_s).to eq("complete")
    end

    it "learns and retires a late item identifier for a parallel call" do
      body = rsp_sse_body [
        rsp_added_function_call("call_one", "echo", output_index: 0),
        rsp_added_function_call("call_two", "read", output_index: 1),
        rsp_args_delta("A", item_id: "new_item", output_index: 0),
        rsp_args_delta("B", item_id: "new_item"),
        rsp_args_done("new_item"),
        # A duplicate must not redirect to the still-active second call.
        rsp_args_delta("wrong", item_id: "new_item", output_index: 1),
        rsp_args_done("new_item", output_index: 1),
        rsp_args_delta("C", item_id: "call_two"),
        rsp_args_done("call_two"),
        rsp_completed,
      ]
      events, msg = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested).map { |e| e["content"] }
      expect(reqs.map { |r| [r["id"].as_s, r["arguments"].as_s] }).to eq([["call_one", "AB"], ["call_two", "C"]])
      expect(msg.tool_calls.not_nil!.map { |c| c.dig("function", "arguments").as_s }).to eq(["AB", "C"])
    end

    it "does not learn aliases from conflicting or retired identifiers" do
      body = rsp_sse_body [
        rsp_added_function_call("call_a", "echo", output_index: 0, wire_id: "item_a"),
        rsp_added_function_call("call_b", "read", output_index: 1, wire_id: "item_b"),
        %q|{"type":"response.function_call_arguments.delta","output_index":0,"item_id":"item_b","call_id":"unknown_conflict","delta":"wrong"}|,
        rsp_args_delta("wrong", item_id: "unknown_conflict"),
        rsp_args_delta("A", item_id: "item_a"),
        rsp_args_done("item_a"),
        %q|{"type":"response.function_call_arguments.delta","output_index":1,"item_id":"item_a","call_id":"unknown_retired","delta":"wrong"}|,
        rsp_args_delta("wrong", item_id: "unknown_retired"),
        rsp_args_delta("B", item_id: "item_b"),
        rsp_args_done("item_b"),
        rsp_completed,
      ]
      events, _ = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested).map { |e| e["content"] }
      expect(reqs.map { |r| [r["id"].as_s, r["arguments"].as_s] }).to eq([["call_a", "A"], ["call_b", "B"]])
    end

    it "retains all identifier-free calls until terminal finalization" do
      body = rsp_sse_body [
        rsp_added_function_call("", "echo", "A"),
        rsp_added_function_call("", "read", "B"),
        rsp_completed,
      ]
      events, msg = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested).map { |e| e["content"] }
      expect(reqs.map { |r| [r["name"].as_s, r["arguments"].as_s] }).to eq([["echo", "A"], ["read", "B"]])
      expect(msg.tool_calls.not_nil!.size).to eq(2)
    end

    it "does not guess for unkeyed events while multiple calls are active" do
      body = rsp_sse_body [
        rsp_added_function_call("call_a", "echo"),
        rsp_added_function_call("call_b", "read"),
        rsp_args_delta("wrong"),
        %q|{"type":"response.function_call_arguments.done","arguments":"wrong"}|,
        rsp_args_delta("A", item_id: "call_a"),
        rsp_args_delta("B", item_id: "call_b"),
        rsp_completed,
      ]
      events, _ = rsp_build_parse_chat.parse_streamed(body)
      reqs = rsp_events_of(events, LLM::Event::ToolCallRequested).map { |e| e["content"] }
      expect(reqs.map { |r| [r["id"].as_s, r["arguments"].as_s] }).to eq([["call_a", "A"], ["call_b", "B"]])
    end

  end
end
