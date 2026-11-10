require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class EnkaiduUniqueModelTestRenderer < WebToolTestRenderer
  getter info_messages = [] of String
  getter warnings = [] of String

  def info_with(message, help = nil, markdown = false) : Nil
    @info_messages << message.to_s
  end

  def warning_with(message, help = nil, markdown = false) : Nil
    @warnings << message.to_s
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

class EnkaiduRecorderTestOptions < Enkaidu::SessionOptions
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
  getter recorder_file : IO?
  getter config_for_llm : Enkaidu::Config::LLM? = nil

  def initialize(@renderer : Enkaidu::SessionRenderer, recorder_file : IO? = nil)
    @config = Enkaidu::Config.from_yaml("")
    @recorder_file = recorder_file
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

  it "construction with unknown unique_model_name warns and falls back" do
    with_ollama_envs do
      renderer = EnkaiduUniqueModelTestRenderer.new
      options = EnkaiduUniqueModelTestOptions.new(renderer, "")
      session = EnkaiduWiretapTestSession.new(renderer, options, "does-not-exist")

      expect(session.id).to_not be_nil
      expect(session.unique_model_name).to eq("does-not-exist")
      expect(renderer.warnings).to contain("Unknown model 'does-not-exist`; using default from config.")
      expect(session.temperature).to be_nil
      expect(session.streaming?).to be_false
      expect(renderer.streaming?).to be_false
    end
  end

  it "construction with load_session_io imports saved session" do
    with_ollama_envs do
      base_renderer = EnkaiduWiretapTestRenderer.new
      base_options = EnkaiduWiretapTestOptions.new(base_renderer, "ollama")
      base = EnkaiduWiretapTestSession.new(base_renderer, base_options)

      io = IO::Memory.new
      base.save_session(io)
      io.rewind

      loaded_renderer = EnkaiduWiretapTestRenderer.new
      loaded_options = EnkaiduWiretapTestOptions.new(loaded_renderer, "ollama")
      loaded = EnkaiduWiretapTestSession.new(loaded_renderer, loaded_options, nil, io)

      expect(loaded.id).to_not be_nil
      expect(loaded.streaming?).to be_false
      expect(loaded_renderer.streaming?).to be_false
    end
  end

  it "construction with invalid load_session_io raises InvalidSessionData" do
    io = IO::Memory.new
    io.puts %({"app":"wrong","ver":"wrong"})
    io.rewind

    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      expect {
        EnkaiduWiretapTestSession.new(renderer, options, nil, io)
      }.to raise_error(Enkaidu::InvalidSessionData)
    end
  end

  it "construction with recorder_file set creates recorder" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      recorder_io = IO::Memory.new
      options = EnkaiduRecorderTestOptions.new(renderer, recorder_io)
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.recorder).to be_a(Enkaidu::Recorder)
    end
  end

  it "construction without recorder_file still creates recorder" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduRecorderTestOptions.new(renderer, nil)
      session = EnkaiduWiretapTestSession.new(renderer, options)

      expect(session.recorder).to be_a(Enkaidu::Recorder)
    end
  end
end
