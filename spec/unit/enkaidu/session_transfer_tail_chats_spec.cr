require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that records `send_tail` invocations (target chat,
# num_responses, filter_by_role).
class TransferTailChatsProbeChat < LLM::Chat
  getter target_chats = [] of LLM::Chat
  getter num_responses = [] of Int32
  getter filter_by_roles = [] of String?

  def send_tail(to : LLM::Chat, num_responses = 1, filter_by_role : String? = nil) : Nil
    @target_chats << to
    @num_responses << num_responses
    @filter_by_roles << filter_by_role
  end

  # No-op: this probe only exercises `send_tail`.
  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end
end

class TransferTailChatsProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session transfer_tail_chats" do
  include LLMSpecHelpers

  # Build the source/target probe pair used by every example.
  def probe_pair(renderer : EnkaiduWiretapTestRenderer, options : EnkaiduWiretapTestOptions)
    source = TransferTailChatsProbeSession.new(renderer, options)
    source_chat = TransferTailChatsProbeChat.new
    source.set_mock_chat(source_chat)

    target = TransferTailChatsProbeSession.new(renderer, options)
    target_chat = TransferTailChatsProbeChat.new
    target.set_mock_chat(target_chat)

    {source: source, source_chat: source_chat, target: target, target_chat: target_chat}
  end

  it "delegates with default num and nil filter_by_role" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      pair = probe_pair(renderer, options)

      pair[:source].transfer_tail_chats(pair[:target])

      # Exactly one delegation on the source chat, carrying the target's chat
      # object, the default num of 1, and a nil filter.
      expect(pair[:source_chat].target_chats).to eq([pair[:target_chat]])
      expect(pair[:source_chat].num_responses).to eq([1])
      expect(pair[:source_chat].filter_by_roles).to eq([nil])
    end
  end

  it "delegates with an explicit num" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      pair = probe_pair(renderer, options)

      pair[:source].transfer_tail_chats(pair[:target], 3)

      expect(pair[:source_chat].target_chats).to eq([pair[:target_chat]])
      expect(pair[:source_chat].num_responses).to eq([3])
      expect(pair[:source_chat].filter_by_roles).to eq([nil])
    end
  end

  it "delegates with an explicit filter_by_role" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      pair = probe_pair(renderer, options)

      pair[:source].transfer_tail_chats(pair[:target], filter_by_role: "assistant")

      expect(pair[:source_chat].target_chats).to eq([pair[:target_chat]])
      expect(pair[:source_chat].num_responses).to eq([1])
      expect(pair[:source_chat].filter_by_roles).to eq(["assistant"])
    end
  end

  it "delegates with explicit num and filter_by_role together" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      pair = probe_pair(renderer, options)

      pair[:source].transfer_tail_chats(pair[:target], 3, "assistant")

      expect(pair[:source_chat].target_chats).to eq([pair[:target_chat]])
      expect(pair[:source_chat].num_responses).to eq([3])
      expect(pair[:source_chat].filter_by_roles).to eq(["assistant"])
    end
  end
end