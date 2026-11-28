require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that records `append_last_response_as_prompt` invocations (target
# chat, prefix, response) and returns a controlled Bool.
class AppendLastResponseProbeChat < LLM::Chat
  getter target_chats = [] of LLM::Chat
  getter prefixes = [] of String
  getter responses = [] of String
  property result = true

  def append_last_response_as_prompt(to : LLM::Chat, prompt_prefix : String, new_response : String) : Bool
    @target_chats << to
    @prefixes << prompt_prefix
    @responses << new_response
    @result
  end

  # No-op: this probe only exercises `append_last_response_as_prompt`.
  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end
end

class AppendLastResponseProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session append_last_response_as_prompt" do
  include LLMSpecHelpers

  it "delegates to the target chat with the prefix and response, returning true" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")

      source = AppendLastResponseProbeSession.new(renderer, options)
      source_chat = AppendLastResponseProbeChat.new
      source.set_mock_chat(source_chat)

      target = AppendLastResponseProbeSession.new(renderer, options)
      target_chat = AppendLastResponseProbeChat.new
      target.set_mock_chat(target_chat)

      result = source.append_last_response_as_prompt(target, "PREFIX", "RESPONSE")

      # Exactly one delegation, carrying the target's chat object, the exact
      # prefix, and the exact response.
      expect(source_chat.target_chats).to eq([target_chat])
      expect(source_chat.prefixes).to eq(["PREFIX"])
      expect(source_chat.responses).to eq(["RESPONSE"])

      # The mock's Bool is passed through unchanged.
      expect(result).to eq(true)
    end
  end

  it "returns false when the mock chat returns false" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")

      source = AppendLastResponseProbeSession.new(renderer, options)
      source_chat = AppendLastResponseProbeChat.new
      source.set_mock_chat(source_chat)

      target = AppendLastResponseProbeSession.new(renderer, options)
      target_chat = AppendLastResponseProbeChat.new
      target.set_mock_chat(target_chat)

      # The delegation is invoked on the source chat, so its controlled Bool
      # is what `Session#append_last_response_as_prompt` passes through.
      source_chat.result = false

      result = source.append_last_response_as_prompt(target, "PREFIX", "RESPONSE")

      expect(source_chat.target_chats).to eq([target_chat])
      expect(source_chat.prefixes).to eq(["PREFIX"])
      expect(source_chat.responses).to eq(["RESPONSE"])

      expect(result).to eq(false)
    end
  end
end