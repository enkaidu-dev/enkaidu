require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe Enkaidu::ConditionalCommandHelper do
  include LLMSpecHelpers

  it "evaluates last_prompt_interrupt conditionals correctly" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)
      session_manager = Enkaidu::SessionManager.new(session)
      helper = Enkaidu::ConditionalCommandHelper.new

      # Initial state is None
      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=none")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Break)

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=tripwire")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Yes)

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=any")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Yes)

      res = helper.handle_conditional_command(session_manager, "?break unless last_prompt_interrupt=tripwire")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Break)

      # Mutate state to Tripwire
      session.last_prompt_interrupt = Enkaidu::PromptInterruptReason::Tripwire

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=tripwire")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Break)

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=any")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Break)

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=user")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Yes)

      res = helper.handle_conditional_command(session_manager, "?break unless last_prompt_interrupt=tripwire")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Yes)

      # Mutate state to User
      session.last_prompt_interrupt = Enkaidu::PromptInterruptReason::User

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=user")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Break)

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=any")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Break)

      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=tripwire")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Yes)

      # Invalid target
      res = helper.handle_conditional_command(session_manager, "?break if last_prompt_interrupt=unknown")
      expect(res[:continue]).to eq(Enkaidu::ConditionalCommandHelper::Continue::Abort)
      expect(res[:message]).to match(/Unknown last_prompt_interrupt target/)
    end
  end
end
