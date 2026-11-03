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

  # Safely pull a string key off an input item (nil when absent / non-string).
  private def jstr(item, key : String) : String?
    raw = item.dig?(key).try(&.raw)
    raw.is_a?(String) ? raw : nil
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

    it "omits the reasoning item when a response is excluded from future requests" do
      chat = build_responses_encoder_chat
      asst = LLM::Message::Response.new("only content", "hidden reasoning")
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
  end
end
