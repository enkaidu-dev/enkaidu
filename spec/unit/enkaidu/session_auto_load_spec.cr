require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session auto_load" do
  include EnkaiduSessionWiretapHelpers

  it "auto_load is a no-op with an empty config" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = EnkaiduWiretapTestSession.new(renderer, options)

      before = renderer.info_messages.dup
      session.auto_load

      expect(renderer.info_messages).to eq(before)
      expect(session.find_system_prompt?("anything")).to be_nil
      expect(session.find_prompt?("anything")).to be_nil
    end
  end

  it "auto_load registers config system prompts and prompts" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      system_prompts:
        greeting:
          template: "Hello"
          description: "greeting system prompt"
      prompts:
        helper:
          template: "Hi"
          description: "helper prompt"
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduWiretapTestSession.new(renderer, options)

      session.auto_load

      expect(renderer.info_messages).to contain("Auto-loading system prompts: greeting")
      expect(renderer.info_messages).to contain("Auto-loading config prompts: helper")
      expect(session.find_system_prompt?("greeting")).to_not be_nil
      expect(session.find_prompt?("helper")).to_not be_nil
    end
  end

  it "auto_load loads toolsets from session config" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      session:
        toolsets: ["DateAndTime"]
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduWiretapTestSession.new(renderer, options)

      session.auto_load

      expect(renderer.info_messages).to contain("Auto-loading toolsets: DateAndTime")
      # `tool_loaded?` returns the tool or `nil`, not a Bool
      expect(session.tool_loaded?("get_current_datetime")).to_not be_nil
    end
  end

  it "auto_load sets the system prompt from session config" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      system_prompts:
        greeting:
          template: "Hello"
      session:
        system_prompt_name: "greeting"
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduWiretapTestSession.new(renderer, options)

      session.auto_load

      expect(session.system_message).to_not be_nil
      expect(session.system_message).to contain("Hello")
    end
  end

  it "auto_load migrates deprecated auto_load settings and applies them" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      system_prompts:
        greeting:
          template: "Hello"
      auto_load:
        system_prompt_name: "greeting"
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduWiretapTestSession.new(renderer, options)

      session.auto_load

      expect(renderer.warnings).to contain("The `auto_load` section is deprecated; use `session` instead.")
      expect(session.system_message).to_not be_nil
      expect(session.system_message).to contain("Hello")
    end
  end
end
