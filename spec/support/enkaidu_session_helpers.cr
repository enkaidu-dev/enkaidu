# Minimal Session options and renderer for Wiretap-backed Enkaidu integration
# specs. Keep this scaffold independent of CLI configuration and side effects.
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

  def initialize(@renderer : Enkaidu::SessionRenderer, @provider_type : String)
    @config = Enkaidu::Config.from_yaml("")
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

# Captures user-visible failures and tool calls while no-oping unrelated UI.
class EnkaiduWiretapTestRenderer < WebToolTestRenderer
  getter errors = [] of String
  getter tool_calls = [] of String

  def error_with(message, help = nil, markdown = false) : Nil
    @errors << message.to_s
  end

  def llm_tool_call(name, args) : Nil
    @tool_calls << name.to_s
  end
end

# Uses a fully initialized Session (including its normal config/system prompt)
# while exposing tool installation for integration specs.
class EnkaiduWiretapTestSession < Enkaidu::Session
  def install_tool(tool : LLM::Function) : Nil
    chat.with_tool(tool)
  end
end

module EnkaiduSessionWiretapHelpers
  include LLMSpecHelpers

  ENKAIDU_SCHEMA_TOOL_PROMPT = "Please echo the word hello using the echo tool. Do not answer in plain text."

  def enkaidu_schema_tool_request_bodies(transcript_name : String) : Array(JSON::Any)
    Wiretap::Transcript.load_or_create(transcript_name, :once).interactions.map do |interaction|
      JSON.parse(interaction.request.body.not_nil!)
    end
  end
end
