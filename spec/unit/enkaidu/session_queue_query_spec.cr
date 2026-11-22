require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# `queue_query` and `take_pending_queries` are public on Enkaidu::Session
# (only the backing `pending_queries` getter is private), so a plain
# EnkaiduWiretapTestSession suffices here - no probe subclass is needed.
Spectator.describe "Enkaidu::Session queue_query and take_pending_queries" do
  include LLMSpecHelpers

  def build_session
    renderer = EnkaiduWiretapTestRenderer.new
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    EnkaiduWiretapTestSession.new(renderer, options)
  end

  it "ignores blank input" do
    with_ollama_envs do
      session = build_session

      session.queue_query("   ")

      expect(session.take_pending_queries).to be_nil
    end
  end

  it "accumulates stripped queries" do
    with_ollama_envs do
      session = build_session

      session.queue_query("one")
      session.queue_query("  two  ")

      expect(session.take_pending_queries).to eq(["one", "two"])
    end
  end

  it "clears the pending queries on take" do
    with_ollama_envs do
      session = build_session

      session.queue_query("one")
      session.queue_query("two")
      taken = session.take_pending_queries

      expect(taken).to eq(["one", "two"])
      expect(session.take_pending_queries).to be_nil
    end
  end

  it "returns nil when empty" do
    with_ollama_envs do
      session = build_session

      expect(session.take_pending_queries).to be_nil
    end
  end
end
