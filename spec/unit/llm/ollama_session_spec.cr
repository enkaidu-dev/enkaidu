require "../../spec_helper"
require "json"

# Guards the "session history is protocol-independent and lossless" invariant
# the refactor relies on: a chat's history can be serialized to JSON and
# reloaded into a *fresh* chat of the same protocol with the conversation and
# the most recent usage intact. Phase 2 lifts `History` into the
# protocol-agnostic base `Chat`, so this round-trip must keep working unchanged.
Spectator.describe LLM::Protocol::ChatCompletions::Chat do
  include LLMSpecHelpers

  describe "#save / #load" do
    it "round-trips a populated history through JSON into a new chat" do
      # History now holds a user prompt + an assistant response.
      chat = populated_ollama_chat

      json = save_chat_json(chat)
      expect(json).not_to be_empty

      # Load into a brand-new chat of the same protocol.
      restored = build_ollama_chat
      restore_chat(restored, json)

      # The conversation survived the round-trip unchanged...
      expect(last_conversation_json(restored)).to eq(last_conversation_json(chat))
      # ...and so did the most recent usage report.
      expect(restored.usage).not_to be_nil
      expect(restored.usage.not_nil!.total_tokens).to eq(chat.usage.not_nil!.total_tokens)
    end
  end
end
