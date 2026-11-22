require "../../spec_helper"
require "../../support/enkaidu_session_helpers"
require "json"

# Mock chat that fails the query with an unexpected server error instead of
# yielding any events. `post_session` is a no-op so the class is concrete;
# `interrupt_and_cleanup` is inherited from `LLM::Chat`.
class RenderingDefaultsProbeChat < LLM::Chat
  def ask(content : String,
          attach : LLM::ChatInclusions? = nil,
          response_schema : LLM::ResponseSchema? = nil,
          exclude_reasoning_in_history = false,
          exclude_reasoning_skip = 0,
          & : LLM::ChatEvent ->) : Nil
    raise LLM::ServerError.new(JSON.parse(%({"error":{"message":"server failure"}})))
  end

  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end
end

# Session probe exposing the mock chat to `ask_sync`.
class RenderingDefaultsProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session rendering defaults" do
  include LLMSpecHelpers

  it "defaults the renderer streaming flag to the session streaming state" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = RenderingDefaultsProbeSession.new(renderer, options)

      expect(options.stream?).to be_false
      expect(renderer.streaming?).to be_false
      expect(session.streaming?).to be_false
      expect(renderer.streaming?).to eq(session.streaming?)
    end
  end

  it "mirrors the renderer streaming flag when streaming is enabled" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama", true)
      session = RenderingDefaultsProbeSession.new(renderer, options)

      expect(options.stream?).to be_true
      expect(renderer.streaming?).to be_true
      expect(session.streaming?).to be_true
      expect(renderer.streaming?).to eq(session.streaming?)
    end
  end

  it "renders query errors through the notify method" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = RenderingDefaultsProbeSession.new(renderer, options)
      session.set_mock_chat(RenderingDefaultsProbeChat.new)

      # The exception must not propagate to the caller.
      session.ask_sync(query: "boom")

      expect(session.last_prompt_interrupt).to eq(Enkaidu::PromptInterruptReason::Error)
      expect(renderer.errors).not_to be_empty
      expect(renderer.errors.first).to contain("Unexpected error")
    end
  end
end
