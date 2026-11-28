require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that records `append_conversations` invocations (target chat,
# conversation selector) and returns a controlled Bool.
class AppendConversationsProbeChat < LLM::Chat
  getter target_chats = [] of LLM::Chat
  getter selectors = [] of LLM::Conversation
  property result = true

  def append_conversations(to : LLM::Chat, which : LLM::Conversation) : Bool
    @target_chats << to
    @selectors << which
    @result
  end

  # No-op: this probe only exercises `append_conversations`.
  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end
end

class AppendConversationsProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session append_conversations" do
  include LLMSpecHelpers

  it "delegates to the target chat with the conversation selector, returning true" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")

      source = AppendConversationsProbeSession.new(renderer, options)
      source_chat = AppendConversationsProbeChat.new
      source.set_mock_chat(source_chat)

      target = AppendConversationsProbeSession.new(renderer, options)
      target_chat = AppendConversationsProbeChat.new
      target.set_mock_chat(target_chat)

      result = source.append_conversations(target, LLM::Conversation::LatestFull)

      # Exactly one delegation, carrying the target's chat object and the
      # exact conversation selector.
      expect(source_chat.target_chats).to eq([target_chat])
      expect(source_chat.selectors).to eq([LLM::Conversation::LatestFull])

      # The mock's Bool is passed through unchanged.
      expect(result).to eq(true)
    end
  end

  it "returns false when the mock chat returns false" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")

      source = AppendConversationsProbeSession.new(renderer, options)
      source_chat = AppendConversationsProbeChat.new
      source.set_mock_chat(source_chat)

      target = AppendConversationsProbeSession.new(renderer, options)
      target_chat = AppendConversationsProbeChat.new
      target.set_mock_chat(target_chat)

      # The delegation is invoked on the source chat, so its controlled Bool
      # is what `Session#append_conversations` passes through.
      source_chat.result = false

      result = source.append_conversations(target, LLM::Conversation::LatestFull)

      expect(source_chat.target_chats).to eq([target_chat])
      expect(source_chat.selectors).to eq([LLM::Conversation::LatestFull])

      expect(result).to eq(false)
    end
  end
end