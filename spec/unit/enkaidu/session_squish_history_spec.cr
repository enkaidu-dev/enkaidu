require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class SquishHistoryProbeSession < EnkaiduWiretapTestSession
  def chat : LLM::Chat
    @chat
  end
end

Spectator.describe "Enkaidu::Session#squish_history" do
  include EnkaiduSessionWiretapHelpers

  def new_session
    renderer = EnkaiduWiretapTestRenderer.new
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = SquishHistoryProbeSession.new(renderer, options)
    {session, renderer}
  end

  it "delegates to chat.squish, reducing history and clearing usage" do
    with_ollama_envs do
      session, renderer = new_session

      # Add a turn with an intermediate response (as in a multi-step tool call)
      # followed by a final response, then a second turn to make squishing meaningful.
      session.chat.append_message(LLM::Message::MultiContent.new("hello"))
      session.chat.append_message(LLM::Message::Response.new("intermediate", nil))
      session.chat.append_message(LLM::Message::Response.new("world", nil))
      session.chat.append_message(LLM::Message::MultiContent.new("next"))
      response = LLM::Message::Response.new("done", nil)
      response.usage = LLM::Usage.from_json(%({"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}))
      session.chat.append_message(response)

      # Verify history was populated and usage is set
      expect(session.chat.usage).not_to be_nil

      # Squish
      result = session.squish_history

      # Verify history was reduced (positive reduction) and usage cleared
      expect(result).to be > 0
      expect(session.chat.usage).to be_nil
      expect(renderer.errors).to be_empty
    end
  end

  it "returns 0 when called on an empty session" do
    with_ollama_envs do
      session, renderer = new_session
      result = session.squish_history
      expect(result).to eq(0)
      expect(renderer.errors).to be_empty
    end
  end
end
