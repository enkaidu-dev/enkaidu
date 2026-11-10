require "../../spec_helper"
require "json"

# Guards the "session history is protocol-independent and lossless" invariant for
# the Responses protocol: a chat's history can be serialized to JSON and
# reloaded into a fresh chat of the same protocol with the conversation and
# the most recent usage intact.
Spectator.describe LLM::Protocol::Responses::Chat do
  include LLMSpecHelpers

  describe "#save / #load" do
    it "round-trips a populated history through JSON into a new chat" do
      chat = populated_ollama_chat(LLM::ProtocolKind::Responses)

      json = save_chat_json(chat)
      expect(json).not_to be_empty

      restored = build_ollama_chat(LLM::ProtocolKind::Responses)
      restore_chat(restored, json)

      expect(last_conversation_json(restored)).to eq(last_conversation_json(chat))
      expect(restored.usage).not_to be_nil
      expect(restored.usage.not_nil!.total_tokens).to eq(chat.usage.not_nil!.total_tokens)
    end
  end
end
