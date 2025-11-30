require "./config_serializable"

module Enkaidu
  # Configuration class facilitates settings for the Enkaidu application.
  class Config < ConfigSerializable
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

    # Configuration for the MCP Server.
    class MCPServer < ConfigSerializable
      getter url : String
      getter transport : String = "auto"
      getter bearer_auth_token : String?
    end

    # Global configuration settings for Enkaidu.
    class Global < ConfigSerializable
      getter? trace_mcp = false
      getter? streaming = false
    end

    # Session configuration settings for Enkaidu.
    class Session < ConfigSerializable
      # Configuration for auto-loading settings within a Session.
      class AutoLoad < ConfigSerializable
        getter mcp_servers : Array(String)?
        getter toolsets : Array(String | NamedTuple(name: String, select: Array(String)))?
      end

      getter provider_type : String?
      getter model : String?
      getter recording_file : String?
      getter input_history_file : String?
      getter auto_load : AutoLoad?
      getter system_prompt : String?
      getter system_prompt_name : String?
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

    getter global : Global?
    getter session : Session?
    getter llms : Hash(String, LLM)?
    getter mcp_servers : Hash(String, MCPServer)?
    getter system_prompts : Hash(String, SystemPrompt)?
    getter prompts : Hash(String, Prompt)?
    getter macros : Hash(String, Macro)?

    # ---------------------- end of content definition

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

    # Config setup helpers and errors and so on

    # Config parsing error
    alias ParseError = YAML::ParseException

    # When more than one default config file is found, because we support
    # more than one extension for YAML
    class TooManyDefaultFiles < Exception
      def initialize(files)
        super("Use one default config file format; only one allowed! Found: #{files.join(", ")}")
      end
    end

    # Not a YAML config file (by extension)
    class UnknownFileFormat < Exception
      def initialize(file_name)
        super("Unknown config file format, only {#{Config::EXTENSIONS.join('|')}} supported! Cannot use: #{file_name}")
      end
    end

    DEFAULT_NAME = "enkaidu"
    EXTENSIONS   = [".yaml", ".yml"]
    FORMATS      = ["YAML"]

    # Parse a config file's contents, and include file name so we can check if
    # it matches known format
    def self.parse(text : String, file_name : String)
      raise UnknownFileFormat.new(file_name) unless EXTENSIONS.any? { |ext| file_name.ends_with?(ext) }
      from_yaml(text)
    end
  end
end
