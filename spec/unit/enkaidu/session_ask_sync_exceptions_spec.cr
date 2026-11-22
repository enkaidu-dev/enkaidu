require "../../spec_helper"
require "../../support/enkaidu_session_helpers"
require "json"

# Mock chat that fails the query with an unexpected server error instead of
# yielding any events. `post_session` is a no-op so the class is concrete;
# `interrupt_and_cleanup` is inherited from `LLM::Chat`.
class AskSyncExceptionsProbeChat < LLM::Chat
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
class AskSyncExceptionsProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session ask_sync exceptions" do
  include LLMSpecHelpers

  it "reports an unexpected error and still closes the recorder" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      recorder_io = IO::Memory.new
      options = EnkaiduRecorderTestOptions.new(renderer, recorder_io)
      session = AskSyncExceptionsProbeSession.new(renderer, options)
      session.set_mock_chat(AskSyncExceptionsProbeChat.new)

      # The exception must not propagate to the caller.
      session.ask_sync(query: "boom")

      expect(session.last_prompt_interrupt).to eq(Enkaidu::PromptInterruptReason::Error)
      expect(renderer.errors.size).to eq(1)
      expect(renderer.errors.first).to match(/Unexpected error, try your prompt again:/)
      expect(renderer.errors.first).to contain("server failure")

      # The recorder still wraps the failed turn: `[` at the start and `]` last.
      recorder_io.rewind
      lines = recorder_io.each_line.map { |line| line.chomp }.reject { |line| line.strip.empty? }.to_a
      expect(lines.join).to contain("[")
      expect(lines.first).to eq("[")
      expect(lines.last).to eq("]")
    end
  end
end