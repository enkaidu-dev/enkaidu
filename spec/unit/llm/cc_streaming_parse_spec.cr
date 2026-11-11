require "../../spec_helper"
require "json"

# Unit tests for the Chat-Completions streaming parser
# (`LLM::Protocol::ChatCompletions::Chat`), i.e. the SSE chunk handling and
# tool-call aggregation
#
# These drive the parser methods directly with hand-built SSE bodies — no HTTP,
# no Wiretap transcript, no live Ollama — so they pin the *wire-shape*
# interpretations and dialect tolerances that the `ollama_*_spec.cr` files
# cannot reach: Ollama's recorded stream collapses each tool call into a single
# chunk, so multi-chunk argument assembly, parallel calls, vLLM's missing
# `arguments` key, the reasoning dialect fields, and malformed-line recovery are
# otherwise untested.
#
# The two methods under test — `#process_data` (one "data:" payload →
# canonical events) and `#prepare_message_from_streamed_data` (a whole stream →
# events + an aggregated `Message::Response`) — are `private`. The thin
# `CCStreamingParseTestChat` subclass below exposes them for testing; because
# Crystal's `private` is visible to descendants, no production signature changes.
#
# Construction is offline: `LLM::Connection#initialize` is empty and the
# endpoint/api-key are only resolved lazily on `#post_and_stream`, none of which
# this spec invokes.

class CCStreamingParseTestChat < LLM::Protocol::ChatCompletions::Chat
  # Parse one whole SSE body; returns the yielded canonical events plus the
  # aggregated `Message::Response` production code would append to history.
  def parse_streamed(sse_body : String) : {Array(LLM::ChatEvent), LLM::Message::Response}
    events = [] of LLM::ChatEvent
    io = IO::Memory.new(sse_body)
    msg = prepare_message_from_streamed_data(io) do |ev|
      events << ev
    end
    {events, msg}
  end

  def stream_events(body : String, &) : Nil
    prepare_message_from_streamed_data(IO::Memory.new(body)) { |event| yield event }
  end

  def json_events(body : String, &) : Nil
    resp = HTTP::Client::Response.new(200, body_io: IO::Memory.new(body))
    handle_app_json(resp) { |event| yield event }
  end

  # Parse one "data:" payload the way `#process_data` does for a single chunk;
  # `from_stream` selects the delta-vs-message selector exactly as production.
  def parse_chunk(data : JSON::Any, from_stream : Bool = true) : Array(LLM::ChatEvent)
    events = [] of LLM::ChatEvent
    process_data(data, from_stream) do |ev|
      events << ev
    end
    events
  end
end

# --- Fixtures -------------------------------------------------------------
# Each builder returns the JSON *text* of one SSE "data:" payload (or a
# JSON::Any for the usage object); `sse_body` frames them as event-stream lines
# and appends the `data: [DONE]` sentinel.

def sse_body(payloads : Array(String), done : Bool = true) : String
  out = String.build do |io|
    payloads.each { |p| io << "data: " << p << "\n\n" }
    io << "data: [DONE]\n\n" if done
  end
  out
end

# A text-content delta as JSON text.
def delta_text(text : String) : String
  JSON.build { |j| j.object { j.field "content", text } }
end

# A reasoning delta using one of the dialect fields
# (`reasoning` / `reasoning_content` / `thinking`).
def delta_reasoning(field : String, text : String) : String
  JSON.build { |j| j.object { j.field field, text } }
end

# A `tool_calls` delta element. Presence of `id`/`name` marks the *start* of a
# call; `arguments` alone (no name) marks a *merge* of argument fragments — the
# exact wire convention `#process_data` keys off. `extra_content` is retained for
# dialect tolerance (some servers attach it).
def tchunk_delta(id : String? = nil, name : String? = nil,
                 arguments : String? = nil, extra_content : JSON::Any? = nil) : String
  JSON.build do |j|
    j.object do
      j.field "tool_calls" do
        j.array do
          j.object do
            j.field "id", id if id
            j.field "index", 0
            j.field "type", "function"
            j.field "function" do
              j.object do
                j.field "name", name if name
                j.field "arguments", arguments if arguments
              end
            end
            j.field "extra_content", extra_content if extra_content
          end
        end
      end
    end
  end
end

def usage_obj(prompt : Int32, completion : Int32, total : Int32) : JSON::Any
  JSON.parse(JSON.build do |j|
    j.object do
      j.field "prompt_tokens", prompt
      j.field "completion_tokens", completion
      j.field "total_tokens", total
    end
  end)
end

# A full SSE "data:" payload (one chat.completion.chunk) as JSON text.
def chunk(delta : String, finish : String? = nil, usage : JSON::Any? = nil) : String
  if usage
    JSON.build do |json|
      json.object do
        json.field "id", "chatcmpl-1"
        json.field "object", "chat.completion.chunk"
        json.field "choices", [] of JSON::Any
        json.field "usage", usage
      end
    end
  else
    JSON.build do |json|
      json.object do
        json.field "id", "chatcmpl-1"
        json.field "object", "chat.completion.chunk"
        json.field "choices" do
          json.array do
            json.object do
              json.field "index", 0
              json.field "delta", JSON.parse(delta)
              json.field "finish_reason", finish if finish
            end
          end
        end
      end
    end
  end
end

# The "empty delta" payload `{}` used for a terminal chunk (e.g. a
# `finish_reason`-only chunk or an Ollama usage chunk).
def empty_delta : String
  "{}"
end

def build_parse_chat : CCStreamingParseTestChat
  CCStreamingParseTestChat.new(LLM::Ollama::Connection.new)
end

def events_of(events, type : LLM::Event) : Array(LLM::ChatEvent)
  events.select { |e| e["type"] == type }
end

Spectator.describe "LLM::Protocol::ChatCompletions::Chat streaming parse" do
  describe "#prepare_message_from_streamed_data (streaming aggregation)" do
    it "assembles a tool call whose arguments arrive across multiple chunks" do
      chat = build_parse_chat
      # Arguments JSON text `{"value": "hello"}`, split across 3 merge fragments.
      body = sse_body [
        chunk(tchunk_delta(id: "call_abc", name: "echo", arguments: "")), # start
        chunk(tchunk_delta(arguments: %q|{"value": |)),                   # merge
        chunk(tchunk_delta(arguments: %q|"hello"}|)),                     # merge
        chunk(empty_delta, finish: "tool_calls"),                         # terminal
      ]
      events, msg = chat.parse_streamed(body)

      # `receiving_tool_call` names one tool; `tool_call_requested` is the canonical
      # closed call, emitted exactly once, in canonical shape (no wire `function` key).
      expect(events_of(events, LLM::Event::ReceivingToolCall).size).to eq(1)
      expect(events_of(events, LLM::Event::ReceivingToolCall).first["content"].as_s).to eq("echo")
      reqs = events_of(events, LLM::Event::ToolCallRequested)
      expect(reqs.size).to eq(1)
      req = reqs.first["content"]
      expect(req["id"].as_s).to eq("call_abc")
      expect(req["name"].as_s).to eq("echo")
      expect(req["arguments"].as_s).to eq(%q|{"value": "hello"}|)
      expect(req.as_h.has_key?("function")).to eq(false) # canonical, not CC wire form

      # History keeps the CC wire shape; the assembled arguments round-trip.
      wire = msg.tool_calls.not_nil!
      expect(wire.size).to eq(1)
      expect(wire.first["type"].as_s).to eq("function")
      expect(wire.first["id"].as_s).to eq("call_abc")
      expect(wire.first.dig("function", "name").as_s).to eq("echo")
      expect(wire.first.dig("function", "arguments").as_s).to eq(%q|{"value": "hello"}|)
      # No text streamed, so content is the empty string (not nil).
      expect(msg.content).to eq("")
    end

    it "wraps multiple tool calls in one stream in order, without cross-contamination" do
      chat = build_parse_chat
      body = sse_body [
        chunk(tchunk_delta(id: "call_1", name: "alpha", arguments: "{}")), # start call_1
        chunk(tchunk_delta(id: "call_2", name: "beta", arguments: "{}")),  # starts call_2, wraps call_1
        chunk(empty_delta, finish: "tool_calls"),                          # wraps call_2
      ]
      events, msg = chat.parse_streamed(body)

      expect(events_of(events, LLM::Event::ReceivingToolCall)
        .map { |e| e["content"].as_s })
        .to eq(["alpha", "beta"])
      expect(events_of(events, LLM::Event::ToolCallRequested)
        .map { |e| e["content"]["name"].as_s })
        .to eq(["alpha", "beta"])
      expect(events_of(events, LLM::Event::ToolCallRequested)
        .map { |e| e["content"]["arguments"].as_s })
        .to eq(["{}", "{}"]) # each call keeps its own args

      wire = msg.tool_calls.not_nil!
      expect(wire.size).to eq(2)
      expect(wire[0].dig("function", "name").as_s).to eq("alpha")
      expect(wire[1].dig("function", "name").as_s).to eq("beta")
    end

    it "captures usage onto the response without forwarding a usage event (streaming path)" do
      chat = build_parse_chat
      body = sse_body [
        chunk(tchunk_delta(id: "call_x", name: "echo", arguments: "")),
        chunk(tchunk_delta(arguments: %q|{"v":1}|)),
        chunk(empty_delta, finish: "tool_calls"),
        chunk(empty_delta, usage: usage_obj(12, 8, 20)),
      ]
      events, msg = chat.parse_streamed(body)

      # Streaming never forwards a `usage` event to the caller; it lands on the response.
      expect(events_of(events, LLM::Event::Usage).size).to eq(0)
      expect(msg.usage).not_to be_nil
      expect(msg.usage.not_nil!.total_tokens).to eq(20)
      expect(msg.usage.not_nil!.prompt_tokens).to eq(12)
      expect(msg.usage.not_nil!.completion_tokens).to eq(8)
    end

    it "assembles streamed refusal text and marks the response" do
      chat = build_parse_chat
      body = sse_body [
        chunk(%|{"refusal":"I can't help with that."}|),
        chunk(empty_delta, finish: "stop"),
      ]
      events, msg = chat.parse_streamed(body)

      expect(events_of(events, LLM::Event::Text).map { |event| event["content"].as_s }).to eq(["I can't help with that."])
      expect(msg.content).to eq("I can't help with that.")
      expect(msg.refusal?).to be_true
      expect(LLM::Message::Response.from_json(msg.to_json).refusal?).to be_true
    end

    it "assembles a single-chunk complete tool call (Ollama shape)" do
      chat = build_parse_chat
      body = sse_body [
        chunk(tchunk_delta(id: "call_o", name: "say", arguments: %q|{"msg":"hi"}|)),
        chunk(empty_delta, finish: "tool_calls"),
      ]
      events, msg = chat.parse_streamed(body)

      req = events_of(events, LLM::Event::ToolCallRequested)
      expect(req.size).to eq(1)
      expect(req.first["content"]["arguments"].as_s).to eq(%q|{"msg":"hi"}|)
      expect(msg.tool_calls.not_nil!.size).to eq(1)
    end
  end

  describe "rate-limit errors and SSE framing" do
    it "warns then raises for both rate-limit types and data prefixes" do
      ["too_many_request", "too_many_requests_error"].each do |type|
        ["data:", "data: "].each do |prefix|
          chat = build_parse_chat
          payload = JSON.parse(%|{"error":{"type":"#{type}","message":"slow down"}}|)
          events = [] of LLM::ChatEvent
          body = "event: error\n: keepalive\n#{prefix}#{payload.to_json}\n\n" + sse_body([chunk(delta_text("unreachable"))])
          expect { chat.stream_events(body) { |event| events << event } }.to raise_error(LLM::TooManyRequests)
          expect(events.map { |event| event["type"] }).to eq([LLM::Event::WarnTooManyRequestsDelay])
          expect(events.first["content"]).to eq(payload)
        end
      end
    end

    it "skips non-data fields even when they end in DONE and accepts unspaced text and DONE" do
      body = "event: [DONE]\n: [DONE]\nid: 1\nretry: 1000\ndata:#{chunk(delta_text("hi"))}\n\ndata:[DONE]\n"
      events, msg = build_parse_chat.parse_streamed(body)
      expect(msg.content).to eq("hi")
      expect(events_of(events, LLM::Event::Done).size).to eq(1)
      expect(events_of(events, LLM::Event::WarnTooManyRequestsDelay).size).to eq(0)
    end

    it "continues SSE parsing for ordinary and null errors without rate-limit warnings" do
      body = sse_body([%|{"error":{"type":"server_error"}}|, %|{"error":null}|, chunk(delta_text("ok"))])
      events, msg = build_parse_chat.parse_streamed(body)
      expect(msg.content).to eq("ok")
      expect(events_of(events, LLM::Event::WarnTooManyRequestsDelay).size).to eq(0)
    end

    it "warns and raises for JSON rate limits but preserves ordinary and null error handling" do
      chat = build_parse_chat
      events = [] of LLM::ChatEvent
      payload = JSON.parse(%|{"error":{"type":"too_many_requests"}}|)
      expect { chat.json_events(payload.to_json) { |event| events << event } }.to raise_error(LLM::TooManyRequests)
      expect(events.map { |event| event["type"] }).to eq([LLM::Event::WarnTooManyRequestsDelay])
      expect(events.first["content"]).to eq(payload)

      events.clear
      expect do
        chat.json_events(%|{"error":{"type":"server_error","message":"too_many_request is not the type"}}|) { |event| events << event }
      end.to raise_error(LLM::ServerError)
      expect(events).to be_empty

      events.clear
      chat.json_events(%|{"error":null,"choices":[{"message":{"content":"ok"}}]}|) { |event| events << event }
      expect(events_of(events, LLM::Event::Text).first["content"].as_s).to eq("ok")
      expect(events_of(events, LLM::Event::WarnTooManyRequestsDelay).size).to eq(0)
    end
  end

  describe "dialects and edge cases (streaming)" do
    it "assembles reasoning across the `reasoning`/`reasoning_content`/`thinking` fields and ignores empty content" do
      chat = build_parse_chat
      body = sse_body [
        chunk(delta_reasoning("reasoning", "a")),
        chunk(delta_text("")), # empty content delta -> no text event
        chunk(delta_reasoning("reasoning_content", "b")),
        chunk(delta_reasoning("thinking", "c")),
        chunk(empty_delta, finish: "stop"),
      ]
      events, msg = chat.parse_streamed(body)

      expect(events_of(events, LLM::Event::Text).size).to eq(0)
      expect(events_of(events, LLM::Event::ReasoningEvent)
        .map { |e| e["content"].as_s })
        .to eq(["a", "b", "c"])
      expect(msg.reasoning).to eq("abc")
      expect(msg.content).to eq("")
    end

    it "retains extra_content for dialect tolerance and echoes it to the wire-form history" do
      chat = build_parse_chat
      ec = JSON.parse(%|{"provider":"vllm"}|)
      body = sse_body [
        chunk(tchunk_delta(id: "call_e", name: "echo", extra_content: ec)),
        chunk(tchunk_delta(arguments: "{}")),
        chunk(empty_delta, finish: "tool_calls"),
      ]
      _events, msg = chat.parse_streamed(body)

      wire = msg.tool_calls.not_nil!
      expect(wire.size).to eq(1)
      expect(wire.first.dig("extra_content", "provider").as_s).to eq("vllm")
    end

    it "recovers from a malformed data line and continues the stream" do
      chat = build_parse_chat
      body = sse_body [
        chunk(delta_text("hi")),
        "{ this is not valid json", # malformed payload -> per-line rescue, keep going
        chunk(delta_reasoning("reasoning", "after")),
      ]
      events, msg = chat.parse_streamed(body)

      expect(events_of(events, LLM::Event::Text).map { |e| e["content"].as_s }).to eq(["hi"])
      expect(events_of(events, LLM::Event::ReasoningEvent).map { |e| e["content"].as_s }).to eq(["after"])
      expect(msg.content).to eq("hi")
      expect(msg.reasoning).to eq("after")
    end

    it "finalizes an in-flight tool call when the stream ends without a finish_reason" do
      chat = build_parse_chat
      # No finish_reason chunk and no [DONE]: historically the in-flight call was
      # dropped (neither emitted nor appended). It must now be finalized at
      # end-of-stream so it still reaches the emitted events and history.
      body = sse_body([
        chunk(tchunk_delta(id: "call_z", name: "echo", arguments: "{}")),
      ], done: false)
      events, msg = chat.parse_streamed(body)

      expect(events_of(events, LLM::Event::ReceivingToolCall).size).to eq(1)
      req = events_of(events, LLM::Event::ToolCallRequested)
      expect(req.size).to eq(1)
      expect(req.first["content"]["id"].as_s).to eq("call_z")
      expect(req.first["content"]["name"].as_s).to eq("echo")
      expect(req.first["content"]["arguments"].as_s).to eq("{}")
      # No [DONE] was sent, so no Done event is fabricated.
      expect(events_of(events, LLM::Event::Done).size).to eq(0)
      # The call was appended to history as well.
      expect(msg.tool_calls.not_nil!.size).to eq(1)
    end

    it "tolerates a start chunk that omits `id` (some vLLM builds) without dropping the call" do
      chat = build_parse_chat
      # No `id` on the start chunk. Pre-hardening this crashed the line into the
      # per-line rescue and dropped the call; it is now extracted with an empty
      # id so the call still flows through and is finalized.
      body = sse_body [
        chunk(tchunk_delta(name: "echo", arguments: "{}")),
        chunk(empty_delta, finish: "tool_calls"),
      ]
      events, msg = chat.parse_streamed(body)

      expect(events_of(events, LLM::Event::ReceivingToolCall).size).to eq(1)
      req = events_of(events, LLM::Event::ToolCallRequested)
      expect(req.size).to eq(1)
      expect(req.first["content"]["name"].as_s).to eq("echo")
      expect(req.first["content"]["arguments"].as_s).to eq("{}")
      expect(req.first["content"]["id"].as_s).to eq("")
      expect(msg.tool_calls.not_nil!.size).to eq(1)
    end
  end

  describe "#process_data (single-chunk mapping)" do
    it "maps a non-streaming tool_calls entry to a canonical shape (no wire function nesting)" do
      chat = build_parse_chat
      data = JSON.parse(%|{"choices":[{"message":{"role":"assistant","content":"hi","tool_calls":[{"id":"c1","type":"function","function":{"name":"echo","arguments":"{}"}}]}}]}|)
      events = chat.parse_chunk(data, from_stream: false)

      expect(events_of(events, LLM::Event::Text).map { |e| e["content"].as_s }).to eq(["hi"])
      req = events_of(events, LLM::Event::ToolCallRequested)
      expect(req.size).to eq(1)
      c = req.first["content"]
      expect(c["id"].as_s).to eq("c1")
      expect(c["name"].as_s).to eq("echo")
      expect(c["arguments"].as_s).to eq("{}")
      expect(c.as_h.has_key?("function")).to eq(false)
    end

    it "emits refusal text as a normal text event" do
      chat = build_parse_chat
      data = JSON.parse(%|{"choices":[{"message":{"content":null,"refusal":"I can't help with that."}}]}|)
      events = chat.parse_chunk(data, from_stream: false)

      expect(events_of(events, LLM::Event::Text).map { |event| event["content"].as_s }).to eq(["I can't help with that."])
    end

    it "emits no events for null content and no finish_reason" do
      chat = build_parse_chat
      data = JSON.parse(%|{"choices":[{"message":{"content":null}}]}|)
      expect(chat.parse_chunk(data, from_stream: false).size).to eq(0)
    end

    it "forwards a finish_reason chunk as a FinishReason event" do
      chat = build_parse_chat
      data = JSON.parse(%|{"choices":[{"message":{},"finish_reason":"stop"}]}|)
      events = chat.parse_chunk(data, from_stream: false)
      frs = events_of(events, LLM::Event::FinishReason)
      expect(frs.size).to eq(1)
      expect(frs.first["content"].as_s).to eq("stop")
    end
  end
end
