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
      getter? enable_shell_command = true
    end

    # Session configuration settings for Enkaidu.
    class Session < ConfigSerializable
      # Configuration for auto-loading settings within a Session.
      class AutoLoad < ConfigSerializable
        getter mcp_servers : Array(String) = [] of String
      end

      getter provider_type : String?
      getter model : String?
      getter recording_file : String?
      getter input_history_file : String?
      getter auto_load : AutoLoad?
    end

    getter global : Global?
    getter session : Session?
    getter llms = {} of String => LLM
    getter mcp_servers = {} of String => MCPServer

    # ---------------------- end of content definition

    # Look for a model by its unique name and, if one exists, return its
    # model's enclosing LLM
    def find_llm_and_model_by?(unique_model_name)
      llms.each do |_, llm|
        llm.models.try &.each do |model|
          if model.name == unique_model_name
            return {llm: llm, model: model}
          end
        end
      end
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

    # Check if a default config file exists
    def self.find_default_file : String?
      exists = [] of String
      EXTENSIONS.each do |ext|
        file = "#{DEFAULT_NAME}#{ext}"
        exists << file if File.exists?(file)
      end

      raise TooManyDefaultFiles.new(exists) if exists.size > 1
      exists[0]?
    end

    # Parse a config file's contents, and include file name so we can check if
    # it matches known format
    def self.parse(text : String, file_name : String)
      raise UnknownFileFormat.new(file_name) unless EXTENSIONS.any? { |ext| file_name.ends_with?(ext) }
      from_yaml(text)
    end
  end
end
