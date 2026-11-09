require "../../spec_helper"
require "../../support/enkaidu_session_helpers"
require "json"

Spectator.describe Enkaidu::Session do
  include LLMSpecHelpers

  it "resets last_prompt_interrupt to None on successful completion" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)

      Wiretap.intercept(LLMSpecHelpers::NON_STREAMING_ASK_TRANSCRIPT) do
        session.ask_sync("First prompt")
      end

      expect(session.last_prompt_interrupt).to eq(Enkaidu::PromptInterruptReason::None)
    end
  end

  it "sets last_prompt_interrupt to User when user interrupt is raised during turn" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = InterruptMockSession.new(renderer, options)
      mock_chat = MockChat.new
      mock_chat.trigger_user_interrupt = true
      mock_chat.session = session
      session.set_mock_chat(mock_chat)

      session.ask_sync("test prompt")

      expect(session.last_prompt_interrupt).to eq(Enkaidu::PromptInterruptReason::User)
    end
  end
end
