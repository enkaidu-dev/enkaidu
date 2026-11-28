require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class EraseHistoryProbeSession < EnkaiduWiretapTestSession
  def chat : LLM::Chat
    @chat
  end
end

Spectator.describe "Enkaidu::Session#erase_history" do
  include EnkaiduSessionWiretapHelpers

  def new_session
    renderer = EnkaiduWiretapTestRenderer.new
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = EraseHistoryProbeSession.new(renderer, options)
    {session, renderer}
  end

  it "delegates to chat.erase_history, clearing usage" do
    with_ollama_envs do
      session, renderer = new_session

      # Add messages to populate the chat history
      session.chat.append_message(LLM::Message::MultiContent.new("hello"))
      response = LLM::Message::Response.new("world", nil)
      response.usage = LLM::Usage.from_json(%({"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}))
      session.chat.append_message(response)

      # Verify history was populated and usage is set
      expect(session.chat.usage).not_to be_nil

      # Erase
      session.erase_history

      # Verify usage is cleared (proves chat.erase_history was called)
      expect(session.chat.usage).to be_nil
      expect(renderer.errors).to be_empty
    end
  end

  it "can be called on an empty session without error" do
    with_ollama_envs do
      session, renderer = new_session
      session.erase_history
      expect(renderer.errors).to be_empty
    end
  end
end
