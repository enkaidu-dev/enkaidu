require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class DummyTemplatePrompt < Enkaidu::TemplatePrompt
  def initialize(@cli : Enkaidu::Session)
    @name = "hello"
    @description = "Dummy description"
    @origin = "test"
    @template = Liquid::Template.parse("Hello Prompt")
  end
end

class TestSession < EnkaiduWiretapTestSession
  def system_message
    chat.system_message
  end

  def add_system_prompt(name : String, prompt)
    system_prompts[name] = prompt
  end
end

Spectator.describe "Enkaidu::Session fork with system prompt" do
  include EnkaiduSessionWiretapHelpers

  it "forks with valid and invalid system_prompt_name handling" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = TestSession.new(renderer, options)
      # Insert a dummy system prompt directly
      dummy_prompt = DummyTemplatePrompt.new(base)
      base.add_system_prompt("hello", dummy_prompt)

      # Fork with valid system prompt name
      forked_valid = TestSession.new(base, true, true, true, "hello")
      # Expect info message about system prompt description
      expect(renderer.info_messages.any? { |msg| msg.includes?("System prompt: Dummy description") }).to be_true
      # Expect system message to include rendered prompt text
      expect(forked_valid.system_message).to contain("Hello Prompt")

      # Fork with invalid system prompt name
      renderer_warnings = EnkaiduWiretapTestRenderer.new
      options2 = EnkaiduWiretapTestOptions.new(renderer_warnings, "ollama")
      base2 = TestSession.new(renderer_warnings, options2)
      base2.auto_load
      original_system_message = base2.system_message

      forked_invalid = TestSession.new(base2, true, true, true, "nonexistent")
      # Expect warning about missing system prompt
      expect(renderer_warnings.warnings.any? { |msg| msg.includes?("Unable to find system prompt named: nonexistent") }).to be_true
      # Expect original system message unchanged
      expect(forked_invalid.system_message).to eq(original_system_message)
    end
  end
end
