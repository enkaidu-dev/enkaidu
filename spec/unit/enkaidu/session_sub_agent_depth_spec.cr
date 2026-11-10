require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session sub_agent_depth" do
  include EnkaiduSessionWiretapHelpers

  it "normal session has sub_agent_depth 0" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = EnkaiduWiretapTestSession.new(renderer, options)

      expect(base.sub_agent_depth).to eq(0)
    end
  end

  it "sub_agent_depth counts nested sub-agents along parent chain" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = EnkaiduWiretapTestSession.new(renderer, options)

      sub1 = EnkaiduWiretapTestSession.new(base, true, true, true, nil, true, true)
      expect(sub1.sub_agent_depth).to eq(1)

      sub2 = EnkaiduWiretapTestSession.new(sub1, true, true, true, nil, true, true)
      expect(sub2.sub_agent_depth).to eq(2)
    end
  end

  it "normal fork with a parent still returns 0" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = EnkaiduWiretapTestSession.new(renderer, options)

      child = EnkaiduWiretapTestSession.new(base, true, true, true, nil, false, false)

      expect(child.parent).to be base
      expect(child.sub_agent_depth).to eq(0)
    end
  end
end
