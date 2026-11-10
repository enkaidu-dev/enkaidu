require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Spec-local probe that exposes the (private) connection provider label via the
# public `LLM.connection_provider_label`, which is reachable because `connection`
# is a protected getter on `Enkaidu::Session`.
class EnkaiduConnectionProviderProbeSession < EnkaiduWiretapTestSession
  def provider_label
    LLM.connection_provider_label(connection)
  end
end

Spectator.describe "Enkaidu::Session connection_provider_type" do
  include EnkaiduSessionWiretapHelpers

  it "defaults the provider to opts.provider_type when no unique_model_name is given" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduConnectionProviderProbeSession.new(renderer, options)

      expect(session.provider_label).to eq("ollama")
    end
  end

  it "overrides the provider via unique_model_name" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama:responses
          models:
            - name: override-model
              model: #{LLMSpecHelpers::MODEL}
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduConnectionProviderProbeSession.new(renderer, options, "override-model")

      expect(session.provider_label).to eq("ollama:responses")
    end
  end
end
