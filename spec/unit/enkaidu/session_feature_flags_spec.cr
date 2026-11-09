require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session feature flags" do
  include EnkaiduSessionWiretapHelpers

  # YAML that sets a session-level feature flag at the top-level `session:` block.
  def session_yaml(flag : Symbol, value : Bool) : String
    <<-YAML
    session:
      #{flag}: #{value}
    YAML
  end

  describe "allow_tool_discovery?" do
    it "defaults to false when config is empty" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_tool_discovery?).to be_false
      end
    end

    it "returns false when explicitly set to false" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(:allow_tool_discovery, false))
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_tool_discovery?).to be_false
      end
    end

    it "returns true when explicitly enabled" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(:allow_tool_discovery, true))
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_tool_discovery?).to be_true
      end
    end
  end

  describe "allow_sub_agents?" do
    it "defaults to false when config is empty" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_sub_agents?).to be_false
      end
    end

    it "returns false when explicitly set to false" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(:allow_sub_agents, false))
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_sub_agents?).to be_false
      end
    end

    it "returns true when explicitly enabled" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(:allow_sub_agents, true))
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_sub_agents?).to be_true
      end
    end
  end

  describe "allow_global_state?" do
    it "defaults to false when config is empty" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_global_state?).to be_false
      end
    end

    it "returns false when explicitly set to false" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(:allow_global_state, false))
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_global_state?).to be_false
      end
    end

    it "returns true when explicitly enabled" do
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduUniqueModelTestOptions.new(renderer, session_yaml(:allow_global_state, true))
        session = EnkaiduWiretapTestSession.new(renderer, options)

        expect(session.allow_global_state?).to be_true
      end
    end
  end
end
