# Minimal Session options and renderer for Wiretap-backed Enkaidu integration
# specs. Keep this scaffold independent of CLI configuration and side effects.

class Enkaidu::Session
  setter last_prompt_interrupt
end

class EnkaiduWiretapTestProfile < Enkaidu::Env::Profile
  def initialize
    super(Path.new("tmp/enkaidu_profile_empty"), EnkaiduWiretapTestRenderer.new, true)
  end
end

class EnkaiduWiretapTestOptions < Enkaidu::SessionOptions
  getter config : Enkaidu::Config
  getter provider_type : String?
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

  def initialize(@renderer : Enkaidu::SessionRenderer, @provider_type : String, @stream : Bool = false)
    @config = Enkaidu::Config.from_yaml("")
  end

  def renderer : Enkaidu::SessionRenderer
    @renderer
  end

  def help : String
    "test options"
  end

  def profile : Enkaidu::Env::Profile
    @profile ||= EnkaiduWiretapTestProfile.new
  end

  def error_and_exit_with(message, help)
    raise Enkaidu::UnexpectedError.new(message)
  end
end

# Captures user-visible failures and tool calls while no-oping unrelated UI.
class EnkaiduWiretapTestRenderer < WebToolTestRenderer
  getter errors = [] of String
  getter tool_calls = [] of String
  getter info_messages = [] of String
  getter warnings = [] of String
  getter responses = [] of String

  def error_with(message, help = nil, markdown = false) : Nil
    @errors << message.to_s
  end

  def llm_tool_call(name, args) : Nil
    @tool_calls << name.to_s
  end

  def info_with(message, help = nil, markdown = false) : Nil
    @info_messages << message.to_s
  end

  def warning_with(message, help = nil, markdown = false) : Nil
    @warnings << message.to_s
  end

  def respond_with(message, help = nil, markdown = false) : Nil
    @responses << message.to_s
  end
end

# Uses a fully initialized Session (including its normal config/system prompt)
# while exposing tool installation for integration specs.
class EnkaiduWiretapTestSession < Enkaidu::Session
  def install_tool(tool : LLM::Function) : Nil
    chat.with_tool(tool)
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

  def profile : Enkaidu::Env::Profile
    @profile ||= EnkaiduWiretapTestProfile.new
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

  def profile : Enkaidu::Env::Profile
    @profile ||= EnkaiduWiretapTestProfile.new
  end

  def error_and_exit_with(message, help)
    raise Enkaidu::UnexpectedError.new(message)
  end
end

# Backward-compatible alias for specs updated from local scaffold.
alias EnkaiduUniqueModelTestRenderer = EnkaiduWiretapTestRenderer

module EnkaiduSessionWiretapHelpers
  include LLMSpecHelpers

  ENKAIDU_SCHEMA_TOOL_PROMPT = "Please echo the word hello using the echo tool. Do not answer in plain text."

  def enkaidu_schema_tool_request_bodies(transcript_name : String) : Array(JSON::Any)
    Wiretap::Transcript.load_or_create(transcript_name, :once).interactions.map do |interaction|
      JSON.parse(interaction.request.body.not_nil!)
    end
  end
end

class InterruptMockSession < EnkaiduWiretapTestSession
  def trigger_user_interrupt!
    interrupt_handler.trigger!
  end

  def set_mock_chat(mock_chat : MockChat)
    @chat = mock_chat
  end
end

class MockChat < LLM::Chat
  property? trigger_user_interrupt = false
  property? trigger_tripwire_interrupt = false
  property session : InterruptMockSession?

  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end

  def ask(content : String, attach = nil, response_schema = nil, exclude_reasoning_in_history = false, exclude_reasoning_skip = 0, & : LLM::ChatEvent ->) : Nil
    if trigger_user_interrupt?
      session.try(&.trigger_user_interrupt!)
    end

    text_content = trigger_tripwire_interrupt? ? ("a" * 100) : "some text"
    event = {type: LLM::Event::Text, content: JSON::Any.new(text_content)}
    yield event
  end
end
