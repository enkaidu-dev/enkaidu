require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class EnkaiduThinkProbeSession < EnkaiduWiretapTestSession
  def current_reasoning : LLM::Reasoning
    chat.reasoning
  end

  def wire_reasoning_effort : String?
    chat.effective_reasoning_effort
  end
end

Spectator.describe "Enkaidu::Session think_map and fallback" do
  include EnkaiduSessionWiretapHelpers

  it "uses built-in reasoning effort levels when no think_map is configured" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama
          models:
            - name: builtin-think-model
              model: #{LLMSpecHelpers::MODEL}
              settings:
                think: high
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduThinkProbeSession.new(renderer, options, "builtin-think-model")
      manager = Enkaidu::SessionManager.new(session)
      think_cmd = Enkaidu::Slash::ThinkCommand.new

      expect(session.current_reasoning).to eq(LLM::Reasoning::High)
      expect(session.wire_reasoning_effort).to eq("high")

      {
        "none"    => {LLM::Reasoning::None, "none"},
        "low"     => {LLM::Reasoning::Low, "low"},
        "medium"  => {LLM::Reasoning::Medium, "medium"},
        "high"    => {LLM::Reasoning::High, "high"},
        "max"     => {LLM::Reasoning::Max, "max"},
        "default" => {LLM::Reasoning::Default, nil},
      }.each do |arg, (expected_enum, expected_wire)|
        think_cmd.handle(manager, CommandParser.new("/think set #{arg}"))
        expect(session.current_reasoning).to eq(expected_enum)
        expect(session.wire_reasoning_effort).to eq(expected_wire)
        expect(renderer.responses.last).to eq("Thinking effort: #{expected_enum}")
      end

      expect(renderer.warnings).to be_empty
    end
  end

  it "maps canonical effort names to model-specific wire strings" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama
          models:
            - name: custom-think-model
              model: #{LLMSpecHelpers::MODEL}
              settings:
                think: max
                think_map:
                  none: minimal
                  max: xhigh
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduThinkProbeSession.new(renderer, options, "custom-think-model")

      expect(session.current_reasoning).to eq(LLM::Reasoning::Max)
      expect(session.wire_reasoning_effort).to eq("xhigh")
      expect(renderer.warnings).to be_empty

      session.reasoning_effort = LLM::Reasoning::None
      expect(session.current_reasoning).to eq(LLM::Reasoning::None)
      expect(session.wire_reasoning_effort).to eq("minimal")
    end
  end

  it "warns and falls back to next lower supported level when a level is mapped to nil" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama
          models:
            - name: capped-think-model
              model: #{LLMSpecHelpers::MODEL}
              settings:
                think_map:
                  max: ~
                  high: ~
                  none: ~
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduThinkProbeSession.new(renderer, options, "capped-think-model")
      manager = Enkaidu::SessionManager.new(session)
      think_cmd = Enkaidu::Slash::ThinkCommand.new

      # `/think set max` (e.g. inside a macro) skips unsupported max & high -> medium
      think_cmd.handle(manager, CommandParser.new("/think set max"))

      expect(session.current_reasoning).to eq(LLM::Reasoning::Medium)
      expect(session.wire_reasoning_effort).to eq("medium")
      expect(renderer.warnings).to contain(
        "Thinking effort 'max' is not supported by #{LLMSpecHelpers::MODEL}; using 'medium' instead.")
      expect(renderer.responses.last).to eq("Thinking effort: Medium")

      # `/think set none` when none is unsupported falls back to default (omits wire parameter)
      renderer.warnings.clear
      think_cmd.handle(manager, CommandParser.new("/think set none"))

      expect(session.current_reasoning).to eq(LLM::Reasoning::Default)
      expect(session.wire_reasoning_effort).to be_nil
      expect(renderer.warnings).to contain(
        "Thinking effort 'none' is not supported by #{LLMSpecHelpers::MODEL}; using 'default' instead.")
      expect(renderer.responses.last).to eq("Thinking effort: Default")
    end
  end

  it "displays the custom wire effort in /think output when mapped to a non-standard name" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama
          models:
            - name: xhigh-model
              model: #{LLMSpecHelpers::MODEL}
              settings:
                think_map:
                  max: xhigh
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduThinkProbeSession.new(renderer, options, "xhigh-model")
      manager = Enkaidu::SessionManager.new(session)
      think_cmd = Enkaidu::Slash::ThinkCommand.new

      think_cmd.handle(manager, CommandParser.new("/think set max"))
      expect(renderer.responses.last).to eq("Thinking effort: Max (xhigh)")
    end
  end

  it "inherits provider-level settings and allows model-level overrides" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama
          settings:
            think: high
            temperature: 0.4
            think_map:
              max: ~
              high: ultra
          models:
            - name: inherited-model
              model: #{LLMSpecHelpers::MODEL}
            - name: overridden-model
              model: #{LLMSpecHelpers::MODEL}
              settings:
                think: max
                temperature: 0.9
                think_map:
                  max: xhigh
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)

      inherited = EnkaiduThinkProbeSession.new(renderer, options, "inherited-model")
      expect(inherited.current_reasoning).to eq(LLM::Reasoning::High)
      expect(inherited.wire_reasoning_effort).to eq("ultra")
      expect(inherited.temperature).to eq(0.4_f32)

      # Also confirms two models sharing the same `model:` string resolve their own `unique_model_name` settings!
      overridden = EnkaiduThinkProbeSession.new(renderer, options, "overridden-model")
      expect(overridden.current_reasoning).to eq(LLM::Reasoning::Max)
      expect(overridden.wire_reasoning_effort).to eq("xhigh")
      expect(overridden.temperature).to eq(0.9_f32)
      # Inherited `high: ultra` from provider think_map is still retained when model only overrides `max`
      overridden.reasoning_effort = LLM::Reasoning::High
      expect(overridden.wire_reasoning_effort).to eq("ultra")
    end
  end

  it "preserves think_map and active reasoning effort across forked sessions" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama
          models:
            - name: fork-think-model
              model: #{LLMSpecHelpers::MODEL}
              settings:
                think: low
                think_map:
                  max: xhigh
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      base = EnkaiduThinkProbeSession.new(renderer, options, "fork-think-model")
      base.reasoning_effort = LLM::Reasoning::Max

      forked = EnkaiduThinkProbeSession.new(base)
      expect(forked.current_reasoning).to eq(LLM::Reasoning::Max)
      expect(forked.wire_reasoning_effort).to eq("xhigh")
    end
  end

  it "exports a valid JSON schema for Config including think_map" do
    schema_json = Enkaidu::Config.json_schema.to_json
    parsed = JSON.parse(schema_json)
    expect(parsed["type"].as_s).to eq("object")
    expect(schema_json).to contain("think_map")
  end
end
