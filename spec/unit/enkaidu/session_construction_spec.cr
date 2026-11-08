require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class EnkaiduUniqueModelTestRenderer < WebToolTestRenderer
  getter info_messages = [] of String

  def info_with(message, help = nil, markdown = false) : Nil
    @info_messages << message.to_s
  end
end

class EnkaiduUniqueModelTestOptions < Enkaidu::SessionOptions
  getter config : Enkaidu::Config
  getter provider_type : String? = "ollama"
  getter model_name : String? = LLMSpecHelpers::MODEL
  getter? debug = false
  getter? stream = false
  getter? quiet = true
  getter? webui = false
  getter? readonly = false
  getter? trace_mcp = false
  getter? cordon_confirmed : Bool? = nil
  getter recorder_file : IO? = nil
  getter config_for_llm : Enkaidu::Config::LLM? = nil

  def initialize(@renderer : Enkaidu::SessionRenderer, yaml : String)
    @config = Enkaidu::Config.from_yaml(yaml)
  end

  def renderer : Enkaidu::SessionRenderer
    @renderer
  end

  def help : String
    "test options"
  end

  def error_and_exit_with(message, help)
    raise Enkaidu::UnexpectedError.new(message)
  end
end

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

  it "construction with valid unique_model_name sets model from config" do
    with_ollama_envs do
      renderer = EnkaiduUniqueModelTestRenderer.new
      unique_name = "unique-test-model"
      yaml = <<-YAML
      llms:
        ollama:
          provider: ollama
          models:
            - name: #{unique_name}
              model: #{LLMSpecHelpers::MODEL}
              settings:
                temperature: 42
                exclude_past_reasoning: 3
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = EnkaiduWiretapTestSession.new(renderer, options, unique_name)

      expect(session.unique_model_name).to eq(unique_name)
      expect(renderer.info_messages).to contain("Using model #{LLMSpecHelpers::MODEL} over ChatCompletions protocol")
      expect(session.temperature).to eq(42)
      expect(session.exclude_past_reasoning?).to be_true
      expect(session.exclude_past_reasoning_from).to eq(3)
      expect(session.streaming?).to be_false
      expect(renderer.streaming?).to be_false
    end
  end
end
