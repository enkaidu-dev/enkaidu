require "../../spec_helper"
require "json"

# Phase 3 golden-file guard for the Responses-protocol encoder
# (`LLM::Protocol::Responses::Encoder`). Pins the wire shape the encoder must
# produce: `instructions` as a top-level field, a flat `input[]` of `message` /
# `reasoning` / `function_call` / `function_call_output` items, the `input_*`
# content-part types, flat tool definitions (no nested `function`),
# `tool_choice: "auto"`, and `text:{format:{json_schema}}` for structured
# output.
#
# The request encoder is a private adapter method; a thin subclass exposes it,
# the same trick `cc_encoder_spec.cr` uses.
Spectator.describe LLM::Protocol::Responses::Chat do
  include LLMSpecHelpers

  class EncoderChat < LLM::Protocol::Responses::Chat
    # Parse the encoded request body the adapter would POST.
    def request_body(response_schema : LLM::ResponseSchema? = nil) : JSON::Any
      JSON.parse(to_body(response_schema))
    end

    def decode_response(body : String) : LLM::Message::Response
      process_responses_json(JSON.parse(body)) { |_| }
    end

    def decode_stream(body : String) : LLM::Message::Response
      prepare_message_from_streamed_data(IO::Memory.new(body)) { |_| }.not_nil!
    end
  end

  private def build_responses_encoder_chat : EncoderChat
    chat = uninitialized EncoderChat
    with_ollama_envs do
      chat = EncoderChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
      chat.with_model("ollama-test")
      chat.with_tool(TestEchoTool.new)
    end
    chat
  end

  # A Chat-Completions-wire tool call as the canonical history stores it; the
  # encoder extracts `{id, function.{name,arguments}}` into a flat item.
  # (Prefixed `rsp_` — `cc_encoder_spec.cr` defines a same-signature helper and
  # Spectator compiles all specs into one program, so the name must be unique.)
  private def rsp_tool_call_json(id = "call_1", name = "echo", arguments = %q|{"value":"hi"}|)
    JSON.parse(%({ "id": #{id.dump}, "function": { "name": #{name.dump}, "arguments": #{arguments.dump} } }))
  end

  describe "request encoding (canonical Message -> Responses wire)" do
    it "encodes instructions, user input, an assistant + tool round-trip, and flat tools" do
      chat = build_responses_encoder_chat
      chat.with_system_message("be terse")
      chat.append_message LLM::Message::MultiContent.new(prompt: "hello there")
      chat.append_message LLM::Message::Response.new("an answer", "let me think", [rsp_tool_call_json])
      chat.append_message LLM::Message::ToolCall.new("call_1", "echo", "hi")

      body = chat.request_body

      # Top-level fields.
      expect(body.dig("instructions").as_s).to eq("be terse")
      expect(body.dig("model").as_s).to eq("ollama-test")
      expect(body.dig("stream")).to eq(false)
      expect(body.dig("tool_choice").as_s).to eq("auto")

      input = body.dig("input").as_a

      # A user message with a single `input_text` part.
      user = input.find { |i| jstr(i, "role") == "user" }.not_nil!
      expect(user.dig("content", 0, "type").as_s).to eq("input_text")
      expect(user.dig("content", 0, "text").as_s).to eq("hello there")

      # Assistant reasoning is resent as a `reasoning` item with a summary.
      reasoning = input.find { |i| jstr(i, "type") == "reasoning" }
      expect(reasoning).not_to be_nil
      expect(reasoning.not_nil!.dig("summary", 0, "text").as_s).to eq("let me think")

      # Assistant text is content with different role
      asst = input.find { |i| jstr(i, "role") == "assistant" }.not_nil!
      expect(asst.dig("content").as_s).to eq("an answer")

      # A flat `function_call` item: no nested `function` key.
      fc = input.find { |i| jstr(i, "type") == "function_call" }.not_nil!
      expect(fc.dig("call_id").as_s).to eq("call_1")
      expect(fc.dig("name").as_s).to eq("echo")
      expect(fc.dig("arguments").as_s).to eq(%q|{"value":"hi"}|)
      expect(fc.as_h.has_key?("function")).to eq(false)

      # A `function_call_output` item that drops the tool name on the wire.
      out_item = input.find { |i| jstr(i, "type") == "function_call_output" }.not_nil!
      expect(out_item.dig("call_id").as_s).to eq("call_1")
      expect(out_item.dig("output").as_s).to eq("hi")
      expect(out_item.as_h.has_key?("name")).to eq(false)

      # Tool definitions are flat (no nested `function`).
      tools = body.dig("tools").as_a
      expect(tools.size).to be(1)
      expect(tools.first.dig("type").as_s).to eq("function")
      expect(tools.first.dig("name").as_s).to eq("echo")
      expect(tools.first.as_h.has_key?("function")).to eq(false)
    end

    it "replays captured output items in their original order" do
      chat = build_responses_encoder_chat
      decoded = chat.decode_response(%q|{"status":"completed","output":[{"type":"reasoning","id":"rs_1","encrypted_content":"blob_1","summary":[{"type":"summary_text","text":"think one"}]},{"type":"function_call","id":"fc_1","call_id":"call_1","name":"echo","arguments":"{}"},{"type":"reasoning","id":"rs_2","encrypted_content":"blob_2","summary":[{"type":"summary_text","text":"think two"}]},{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"answer"}]}]}|)
      chat.append_message decoded

      input = chat.request_body["input"].as_a
      expect(input.map { |item| item["type"]?.try(&.as_s?) || item["role"].as_s }).to eq([
        "reasoning", "function_call", "reasoning", "assistant",
      ])
      expect(input[0]["id"].as_s).to eq("rs_1")
      expect(input[1]["call_id"].as_s).to eq("call_1")
      expect(input[2]["id"].as_s).to eq("rs_2")
      expect(input[3].dig("content", 0, "text").as_s).to eq("answer")
    end

    it "orders completed streaming items by output_index, not arrival order" do
      chat = build_responses_encoder_chat
      stream = %(data: {"type":"response.output_item.done","output_index":1,"item":{"type":"message","content":[{"type":"output_text","text":"answer"}]}}\n\ndata: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_first","encrypted_content":"blob_first","summary":[]}}\n\ndata: {"type":"response.completed","response":{"status":"completed"}}\n\n)
      decoded = chat.decode_stream(stream)
      chat.append_message decoded

      input = chat.request_body["input"].as_a
      expect(input.map { |item| item["type"]?.try(&.as_s?) || item["role"].as_s }).to eq(["reasoning", "assistant"])
      expect(input.first["id"].as_s).to eq("rs_first")
      expect(input.last.dig("content", 0, "text").as_s).to eq("answer")
    end

    it "persists the Responses sidecar in serialized message history" do
      chat = build_responses_encoder_chat
      decoded = chat.decode_response(%q|{"status":"completed","output":[{"type":"function_call","call_id":"call_1","name":"echo","arguments":"{}"},{"type":"message","content":[{"type":"output_text","text":"done"}]}]}|)
      restored = LLM::Message::Response.from_json(decoded.to_json)
      chat.erase_history
      chat.append_message restored

      input = chat.request_body["input"].as_a
      expect(input.map { |item| item["type"]?.try(&.as_s?) || item["role"].as_s }).to eq(["function_call", "assistant"])
    end

    it "uses canonical projections when no Responses sidecar exists" do
      chat = build_responses_encoder_chat
      chat.append_message LLM::Message::Response.new("legacy answer", "legacy thought", [rsp_tool_call_json])

      input = chat.request_body["input"].as_a
      expect(input.map { |item| item["type"]?.try(&.as_s?) || item["role"].as_s }).to eq([
        "reasoning", "assistant", "function_call",
      ])
      expect(input[1].dig("content").as_s).to eq("legacy answer")
      expect(input[2]["call_id"].as_s).to eq("call_1")
    end

    it "omits the reasoning item when a response is excluded from future requests" do
      chat = build_responses_encoder_chat
      asst = LLM::Message::Response.new("only content", "hidden reasoning", reasoning_id: "rs_hidden", encrypted_content: "hidden_blob")
      asst.include_reasoning = false
      chat.append_message asst

      input = chat.request_body["input"].as_a
      reasoning = input.find { |i| jstr(i, "type") == "reasoning" }
      expect(reasoning).to be_nil
    end

    it "encodes a response schema as text.format.json_schema" do
      chat = build_responses_encoder_chat
      chat.append_message LLM::Message::MultiContent.new(prompt: "q")
      schema = LLM::ResponseSchema.from_json(
        %|{"name":"Answer","description":"a flag","schema":{"type":"object","properties":{"ok":{"type":"boolean"}}},"strict":true}|)

      body = chat.request_body(schema)
      expect(body.dig("text", "format", "type").as_s).to eq("json_schema")
      expect(body.dig("text", "format", "strict")).to eq(true)
      expect(body.dig("text", "format", "name").as_s).to eq("Answer")
    end

    it "encodes reasoning effort settings and include fields" do
      chat = build_responses_encoder_chat
      chat.with_reasoning(LLM::Reasoning::Low)
      body = chat.request_body
      expect(body.dig("reasoning", "effort").as_s).to eq("low")
      expect(body.dig("reasoning", "summary").as_s).to eq("auto")
      expect(body.dig("include", 0).as_s).to eq("reasoning.encrypted_content")

      chat_none = build_responses_encoder_chat
      chat_none.with_reasoning(LLM::Reasoning::None)
      body_none = chat_none.request_body
      expect(body_none.dig("reasoning", "effort").as_s).to eq("none")
      expect(body_none.as_h.has_key?("include")).to eq(false)
    end

    it "replays encrypted reasoning decoded from JSON with empty or absent summaries" do
      [
        %q|{"type":"reasoning","id":"rs_empty","encrypted_content":"blob_empty","summary":[]}|,
        %q|{"type":"reasoning","id":"rs_absent","encrypted_content":"blob_absent"}|,
      ].each do |item|
        chat = build_responses_encoder_chat
        decoded = chat.decode_response(%|{"status":"completed","output":[#{item}]}|)
        source = JSON.parse(item)
        expect(decoded.reasoning).to be_nil
        expect(decoded.reasoning_id).to eq(source["id"].as_s)
        expect(decoded.encrypted_content).to eq(source["encrypted_content"].as_s)
        chat.append_message decoded

        input = chat.request_body["input"].as_a
        replay = input.find { |i| jstr(i, "type") == "reasoning" }
        expect(replay).not_to be_nil
        if replay
          expect(replay["id"].as_s).to eq(source["id"].as_s)
          expect(replay["encrypted_content"].as_s).to eq(source["encrypted_content"].as_s)
          expect(replay["summary"].as_a).to be_empty
        end

        decoded.include_reasoning = false
        expect(chat.request_body["input"].as_a.find { |i| jstr(i, "type") == "reasoning" }).to be_nil
      end
    end

    it "replays encrypted reasoning decoded from a stream without summary deltas" do
      chat = build_responses_encoder_chat
      stream = %(data: {"type":"response.output_item.done","item":{"type":"reasoning","id":"rs_stream","encrypted_content":"blob_stream","summary":[]}}\n\ndata: {"type":"response.completed","response":{"status":"completed"}}\n\n)
      decoded = chat.decode_stream(stream)
      expect(decoded.reasoning).to eq("")
      expect(decoded.reasoning_id).to eq("rs_stream")
      expect(decoded.encrypted_content).to eq("blob_stream")
      chat.append_message decoded

      replay = chat.request_body["input"].as_a.find { |i| jstr(i, "type") == "reasoning" }
      expect(replay).not_to be_nil
      if replay
        expect(replay["id"].as_s).to eq("rs_stream")
        expect(replay["encrypted_content"].as_s).to eq("blob_stream")
        expect(replay["summary"].as_a).to be_empty
      end

      decoded.include_reasoning = false
      expect(chat.request_body["input"].as_a.find { |i| jstr(i, "type") == "reasoning" }).to be_nil
    end

    it "does not replay empty reasoning without encrypted content" do
      [nil, "", "  "].each do |thoughts|
        chat = build_responses_encoder_chat
        chat.append_message LLM::Message::Response.new("answer", thoughts, reasoning_id: "rs_only")
        expect(chat.request_body["input"].as_a.find { |i| jstr(i, "type") == "reasoning" }).to be_nil
      end
    end

    it "encodes historical reasoning with reasoning_id and encrypted_content" do
      chat = build_responses_encoder_chat
      asst = LLM::Message::Response.new("done", "thinking", reasoning_id: "rs_123", encrypted_content: "encrypted_blob")
      chat.append_message asst

      input = chat.request_body["input"].as_a
      reasoning = input.find { |i| jstr(i, "type") == "reasoning" }.not_nil!
      expect(reasoning.dig("id").as_s).to eq("rs_123")
      expect(reasoning.dig("encrypted_content").as_s).to eq("encrypted_blob")
      expect(reasoning.dig("summary", 0, "text").as_s).to eq("thinking")
    end
  end
end
