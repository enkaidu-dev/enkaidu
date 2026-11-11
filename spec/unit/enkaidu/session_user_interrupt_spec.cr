require "../../spec_helper"
require "../../support/enkaidu_session_helpers"
require "json"

Spectator.describe Enkaidu::Session do
  include LLMSpecHelpers

  it "resets last_prompt_interrupt to None on successful completion" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = InterruptMockSession.new(renderer, options)
      mock_chat = MockChat.new
      mock_chat.session = session
      session.set_mock_chat(mock_chat)
      session.last_prompt_interrupt = Enkaidu::PromptInterruptReason::Error

      session.ask_sync("First prompt")

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

  it "sets last_prompt_interrupt to Error and cleans up history when an error is raised during turn" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = InterruptMockSession.new(renderer, options)
      mock_chat = MockChat.new
      mock_chat.trigger_error = true
      mock_chat.session = session
      session.set_mock_chat(mock_chat)

      session.ask_sync("test prompt")

      expect(session.last_prompt_interrupt).to eq(Enkaidu::PromptInterruptReason::Error)
      expect(renderer.errors).not_to be_empty

      conversations = mock_chat.extract_conversations(LLM::Conversation::SessionFull)
      expect(conversations).not_to be_nil
      if conv_json = conversations
        parsed = JSON.parse(conv_json).as_a
        expect(parsed.size).to eq(2)
        expect(parsed[0]["role"].as_s).to eq("user")
        expect(parsed[1]["role"].as_s).to eq("assistant")
        expect(parsed[1]["content"].as_s).to contain("[Unexpected error:")
      end
    end
  end
end
