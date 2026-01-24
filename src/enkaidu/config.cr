require "./config_serializable"

module Enkaidu
  # Config parsing error
  alias ConfigParseError = YAML::ParseException

  CONFIG_EXTENSIONS = [".yaml", ".yml"]
  CONFIG_FORMATS    = ["YAML"]

  # When more than one default file is found, because we support
  # more than one extension for YAML
  class TooManyDefaultConfigFiles < Exception
    def initialize(files)
      super("Use one default config file format; only one allowed! Found: #{files.join(", ")}")
    end
  end

  # Not an expected config file (by extension)
  class UnknownConfigFileFormat < Exception
    def initialize(file_name)
      super("Unknown config file format, only {#{CONFIG_EXTENSIONS.join('|')}} supported! Cannot use: #{file_name}")
    end
  end

  # Profile level configuration facilitates minimal settings that can be specified in the profile folder
  class ProfileConfig < ConfigSerializable
    # Autoload session settings for Enkaidu.
    class AutoLoad < ConfigSerializable
      getter_with_presence mcp_servers, Array(String)?
      getter_with_presence toolsets, Array(String | NamedTuple(name: String, select: Array(String)))?
      getter_with_presence system_prompt, String?
      getter_with_presence system_prompt_name, String?

      protected def merge(from : AutoLoad)
        @mcp_servers = from.mcp_servers unless mcp_servers_present?
        @toolsets = from.toolsets unless toolsets_present?
        @system_prompt = from.system_prompt unless system_prompt_present?
        @system_prompt_name = from.system_prompt_name unless system_prompt_name_present?
      end
    end

    alias ToolSettings = Hash(String, Tools::Settings)

    getter_with_presence auto_load, AutoLoad?

    getter tool_settings : ToolSettings?
  end

  # Application level configuration class facilitates settings for the Enkaidu application.
  class Config < ProfileConfig
    DEFAULT_NAME = "enkaidu"

    # ---------------------- start of content definition

    # Represents a Language Model configuration within the Enkaidu application.
    class LLM < ConfigSerializable
      # Represents a Model within an LLM.
      class Model < ConfigSerializable
        getter name : String
        getter model : String
      end

      getter provider : String
      getter models : Array(Model)?
      # Use this to populate environment variables for the specific
      # provider and they will be passed through
      getter env = {} of String => String
    end

    # Debug configuration settings for Enkaidu.
    class Debug < ConfigSerializable
      getter? trace_mcp = false
    end

    # Session configuration settings for Enkaidu.
    class Session < ConfigSerializable
      getter? streaming = false
      getter provider_type : String?
      getter model : String?
      getter input_history_file : String?
    end

    # Configuration for the MCP Server.
    class MCPServer < ConfigSerializable
      getter url : String
      getter transport : String = "auto"
      getter bearer_auth_token : String?
    end

    class SystemPrompt < ConfigSerializable
      getter template : String
      getter description : String?
    end

    class Macro < ConfigSerializable
      getter description : String
      getter queries : Array(String)
    end

    class Prompt < ConfigSerializable
      class Arg < ConfigSerializable
        getter description : String
      end

      getter description : String
      getter arguments : Hash(String, Arg)?
      getter template : String
    end

    getter debug : Debug?
    getter session : Session?
    getter llms : Hash(String, LLM)?

    getter mcp_servers : Hash(String, MCPServer)?
    getter system_prompts : Hash(String, SystemPrompt)?
    getter prompts : Hash(String, Prompt)?
    getter macros : Hash(String, Macro)?

    # ---------------------- end of content definition

    # Return tool settings if any
    def tool_settings_by_name(tool_name : String) : Tools::Settings?
      tool_settings.try &.[tool_name]?
    end

    # Merge in a profile configuration, using settings from the profile
    # configuration when none have been specific in the app configuration
    def merge_profile_config(profile_config : ProfileConfig, renderer)
      if profile_auto_load = profile_config.auto_load
        merge_profile_autoload_config(profile_auto_load, renderer)
      end

      if profile_tool_settings = profile_config.tool_settings
        merge_profile_tool_settings(profile_tool_settings, renderer)
      end
    end

    # Merge tool settings config from profile
    private def merge_profile_tool_settings(profile_tool_settings : ProfileConfig::ToolSettings, renderer)
      if my_tool_settings = tool_settings
        # Merge with config's tool settings having priority
        my_tool_settings.merge!(profile_tool_settings) do |_key, config_value, _profile_value|
          config_value
        end
      else
        # no override, so use from profile
        @tool_settings = profile_tool_settings
      end
    end

    # Merge auto_load config from profile
    private def merge_profile_autoload_config(profile_auto_load : ProfileConfig::AutoLoad, renderer)
      if my_auto_load = auto_load
        # not nil
        my_auto_load.merge(profile_auto_load)
      elsif auto_load_present?
        # nil set explicitly in app config
        renderer.warning_with("WARN: Using `auto_load: nil` from app config, IGNORING `auto_load` in profile config.")
      else
        # no override, so use from profile
        @auto_load = profile_auto_load
      end
    end

    # Look for a model by its unique name and, if one exists, return its
    # model's enclosing LLM
    def find_llm_and_model_by?(unique_model_name)
      llms.try &.each do |_, llm|
        llm.models.try &.each do |model|
          if model.name == unique_model_name
            return {llm: llm, model: model}
          end
        end
      end
    end

    # Look for an MCP server based on its url and return its name
    # in the config, or `nil` if not found.
    def find_mcp_server_by_url?(url : String)
      mcp_servers.try &.each do |name, spec|
        return name if spec.url == url
      end
      nil
    end

    # Given a path, look for the supported config file name/extension variants
    def self.find_config_file(path : Path, base_name = DEFAULT_NAME) : Path?
      found = [] of Path
      CONFIG_EXTENSIONS.each do |ext|
        file_path = Path.new(path, "#{base_name}#{ext}")
        found << file_path if File.exists?(file_path)
      end

      raise TooManyDefaultConfigFiles.new(found) if found.size > 1
      found.first?
    end
  end
end
