require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session construction" do
  include EnkaiduSessionWiretapHelpers

  it "default construction sets basic state" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.id).to_not be_nil
      expect(session.id).to match(/^[0-9a-fA-F]{8}-/)
      expect(session.parent).to be_nil
      expect(session.sub_agent?).to be_false
      expect(session.unique_model_name).to be_nil
      expect(session.recorder).to be_a(Enkaidu::Recorder)
      expect(session.renderer).to be renderer
      expect(session.streaming?).to be_false
      expect(renderer.streaming?).to be_false
    end
  end
end
