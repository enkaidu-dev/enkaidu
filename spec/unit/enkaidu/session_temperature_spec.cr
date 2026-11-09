require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session temperature" do
  include EnkaiduSessionWiretapHelpers

  # YAML that sets `temperature` in a model's settings, mirroring the
  # construction spec's llms.ollama.models layout. The model's `name` is the
  # unique name passed to the session so `@model_config` resolves.
  def model_yaml(unique_name : String, temperature) : String
    <<-YAML
    llms:
      ollama:
        provider: ollama
        models:
          - name: #{unique_name}
            model: #{LLMSpecHelpers::MODEL}
            settings:
              temperature: #{temperature}
    YAML
  end

  it "returns nil when there are no model settings" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.temperature).to be_nil
    end
  end

  it "returns an integer temperature from model settings" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      unique_name = "temp-int-model"
      yaml = model_yaml(unique_name, 42)
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduWiretapTestSession.new(renderer, options, unique_name)

      expect(session.temperature).to eq(42)
    end
  end

  it "returns a float temperature from model settings" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      unique_name = "temp-float-model"
      yaml = model_yaml(unique_name, 0.7)
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduWiretapTestSession.new(renderer, options, unique_name)

      expect(session.temperature).to eq(0.7_f32)
    end
  end
end
