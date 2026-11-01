require "../../spec_helper"
require "json"

# Phase 2 step-1 guardrails. Before this phase the canonical `Message` classes
# carried a `to_protocol_json`/`protocol_fields_to_json` bridge that doubled as the
# request encoder; the bridge is now gone and the request body is produced by the
# adapter's `encode_message`. These tests pin:
#   * the per-message wire shape the encoder must reproduce (role-ordered fields,
#     the `Message::Response` reasoning field being gated on `include_reasoning?`
#     -- which the canonical `to_json` save format does NOT do -- and conditional
#     `content`/`tool_calls`), and
#   * that the canonical save/restore format round-trips through the lifted
#     `save`/`load`/`extract_conversations` (the Phase 2 acceptance invariant).
#
# The request encoder is a private adapter method; a thin subclass exposes it, the
# same trick `cc_streaming_parse_spec.cr` uses for the SSE parser.
Spectator.describe LLM::Protocol::ChatCompletions::Chat do
  include LLMSpecHelpers

  class EncoderChat < LLM::Protocol::ChatCompletions::Chat
    # Parse the encoded request body the adapter would POST.
    def request_body(response_schema : LLM::ResponseSchema? = nil) : JSON::Any
      JSON.parse(to_body(response_schema))
    end
  end

  private def build_encoder_chat : EncoderChat
    chat = uninitialized EncoderChat
    with_ollama_envs do
      chat = EncoderChat.new(LLM::Ollama::Connection.new)
      chat.with_model("ollama-test")
    end
    chat
  end

  # A Chat-Completions-wire tool call: {id, function:{name, arguments}}.
  private def tool_call_json(id = "call_1", name = "echo", arguments = %({"value":"hi"}))
    JSON.parse(%({ "id": #{id.dump}, "function": { "name": #{name.dump}, "arguments": #{arguments.dump} } }))
  end

  private def messages_of(chat : EncoderChat)
    chat.request_body["messages"].as_a
  end

  private def find_message(messages, role : String)
    messages.find { |m| m["role"].as_s == role }.not_nil!
  end

  describe "request encoding (canonical Message -> CC wire)" do
    it "encodes system prompt, user, assistant (reasoning + tool_calls), and tool result" do
      chat = build_encoder_chat
      chat.with_system_message("be terse")
      chat.append_message LLM::Message::MultiContent.new(prompt: "hello there")
      chat.append_message LLM::Message::Response.new("an answer", "let me think", [tool_call_json])
      chat.append_message LLM::Message::ToolCall.new("call_1", "echo", "hi")

      messages = messages_of(chat)

      # The system prompt precedes the transcript messages.
      expect(find_message(messages, "system")["content"].as_s).to eq("be terse")

      user = find_message(messages, "user")
      expect(user["content"].as_a.size).to eq(1)

      asst = find_message(messages, "assistant")
      expect(asst["content"].as_s).to eq("an answer")
      expect(asst["reasoning"].as_s).to eq("let me think")
      expect(asst["tool_calls"].as_a.map { |c| c["function"]["name"].as_s }).to contain("echo")

      tool = find_message(messages, "tool")
      expect(tool["tool_call_id"].as_s).to eq("call_1")
      expect(tool["name"].as_s).to eq("echo")
      expect(tool["content"].as_s).to eq("hi")
    end

    it "omits reasoning when include_reasoning? is false and omits empty content/tool_calls" do
      chat = build_encoder_chat
      asst = LLM::Message::Response.new("only content", "hidden reasoning")
      asst.include_reasoning = false
      chat.append_message asst
      # A response with nil content and nil tool_calls still encodes as a valid entry.
      chat.append_message LLM::Message::Response.new(nil, nil)

      # The first appended assistant message is the "only content" one above.
      target = chat.request_body["messages"].as_a.find { |m| m["role"].as_s == "assistant" }.not_nil!
      expect(target["content"].as_s).to eq("only content")
      # Reasoning present on the object but excluded from the request, and no
      # (empty) tool_calls field emitted.
      expect(target.dig?("reasoning")).to be_nil
      expect(target.dig?("tool_calls")).to be_nil
    end
  end

  describe "canonical save/restore round-trip" do
    it "round-trips a mixed transcript through the lifted save/load path" do
      chat = build_encoder_chat
      chat.append_message LLM::Message::MultiContent.new(prompt: "q1")
      chat.append_message LLM::Message::Response.new("a1", "thinking", nil)
      chat.append_message LLM::Message::ToolCall.new("call_1", "echo", "out")

      json = save_chat_json(chat)
      fresh = build_encoder_chat
      restore_chat(fresh, json)

      expect(last_conversation_json(fresh)).to eq(last_conversation_json(chat))
    end
  end
end
