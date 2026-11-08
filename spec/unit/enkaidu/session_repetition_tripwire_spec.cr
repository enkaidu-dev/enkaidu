require "../../spec_helper"
require "../../support/enkaidu_session_helpers"
require "json"

Spectator.describe Enkaidu::Session do
  include LLMSpecHelpers

  it "repetition_tripwire? defaults to true when session config is not present" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.repetition_tripwire?).to be_true
    end
  end

  it "trips when repetitive text is fed to text_tripwire" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)

      session.text_tripwire << "a" * 100
      expect(session.text_tripwire.tripped?).to be_true

      trip = session.text_tripwire.trip
      expect(trip).not_to be_nil
      expect(trip.not_nil!.check).to eq(RepetitionTripwire::Check::Run)
    end
  end
end
