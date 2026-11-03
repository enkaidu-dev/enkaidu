require "../../spec_helper"
require "json"

# Guards the "sessions are portable across chats" invariant for the Responses
# protocol: `fork` copies a peer chat's history into this one by value, leaving
# the source untouched, with an option to drop the most recent turn.
Spectator.describe LLM::Protocol::Responses::Chat do
  include LLMSpecHelpers

  describe "#fork" do
    it "copies a peer's conversation into a fresh chat" do
      parent = populated_ollama_chat(LLM::ProtocolKind::Responses)
      child = build_ollama_chat(LLM::ProtocolKind::Responses)

      child.fork(parent)

      expect(last_conversation_json(child)).to eq(last_conversation_json(parent))
    end

    it "leaves the source chat untouched by the copy" do
      parent = populated_ollama_chat(LLM::ProtocolKind::Responses)
      before = last_conversation_json(parent)

      child = build_ollama_chat(LLM::ProtocolKind::Responses)
      child.fork(parent)
      child.erase_history

      expect(last_conversation_json(parent)).to eq(before)
    end

    it "drops the most recent turn when excluding it" do
      parent = populated_ollama_chat(LLM::ProtocolKind::Responses)
      child = build_ollama_chat(LLM::ProtocolKind::Responses)

      child.as(LLM::Protocol::Responses::Chat).fork(parent, exclude_last_turn: true)

      # The only turn was the just-completed one, so the child is left empty.
      expect(last_conversation_json(child)).to eq("[]")
      expect(last_conversation_json(child)).not_to eq(last_conversation_json(parent))
    end
  end
end
