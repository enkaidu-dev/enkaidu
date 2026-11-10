require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session exclude_past_reasoning?" do
  include EnkaiduSessionWiretapHelpers

  # YAML that sets `exclude_past_reasoning` at the top-level `session:` block.
  def session_yaml(value : Bool | Int32?) : String
    <<-YAML
    session:
      exclude_past_reasoning: #{value}
    YAML
  end

  # YAML that sets `exclude_past_reasoning` in a model's settings, mirroring
  # the construction spec's llms.ollama.models layout.
  def model_yaml(value : Bool | Int32?) : String
    <<-YAML
    llms:
      ollama:
        provider: ollama
        models:
          - name: exmr-model
            model: #{LLMSpecHelpers::MODEL}
            settings:
              exclude_past_reasoning: #{value}
    YAML
  end

  it "defaults to false when config is empty (nil value)" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.exclude_past_reasoning?).to be_false
    end
  end

  it "session-level nil returns false" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(nil))
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.exclude_past_reasoning?).to be_false
    end
  end

  it "session-level configured false returns false" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(false))
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.exclude_past_reasoning?).to be_false
    end
  end

  it "session-level configured true returns true" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(true))
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.exclude_past_reasoning?).to be_true
    end
  end

  it "session-level positive numeric returns true" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(5))
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.exclude_past_reasoning?).to be_true
    end
  end

  it "session-level negative numeric returns false" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(-5))
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.exclude_past_reasoning?).to be_false
    end
  end

  it "model settings configured true returns true" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, model_yaml(true))
      session = EnkaiduWiretapTestSession.new(renderer, options, "exmr-model")

      expect(session.exclude_past_reasoning?).to be_true
    end
  end

  it "model settings configured false returns false" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, model_yaml(false))
      session = EnkaiduWiretapTestSession.new(renderer, options, "exmr-model")

      expect(session.exclude_past_reasoning?).to be_false
    end
  end

  it "model settings positive numeric returns true" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, model_yaml(5))
      session = EnkaiduWiretapTestSession.new(renderer, options, "exmr-model")

      expect(session.exclude_past_reasoning?).to be_true
    end
  end

  it "model settings negative numeric returns false" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, model_yaml(-5))
      session = EnkaiduWiretapTestSession.new(renderer, options, "exmr-model")

      expect(session.exclude_past_reasoning?).to be_false
    end
  end
end
