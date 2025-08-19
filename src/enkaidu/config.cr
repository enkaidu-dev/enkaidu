require "./config_serializable"

module Enkaidu
  # Configuration
  class Config < ConfigSerializable
    # ---------------------- start of content definition

    class Model < ConfigSerializable
      getter name : String
      getter model : String
    end

    class LLM < ConfigSerializable
      getter provider : String
      getter models : Array(Model)?
      # Use this to populate environment variables for the specific
      # provider and they will be passed through
      getter env = {} of String => String
    end

    class Options < ConfigSerializable
      getter provider_type : String?
      getter model : String?
      getter recording_file : String?
      getter? trace_mcp = false
      getter? streaming = false
      getter? enable_shell_command = true
    end

    getter default : Options?
    getter llms = {} of String => LLM

    # ---------------------- end of content definition

    # Look for a model by its unique name and, if one exists, return its
    # model's enclosing LLM
    def find_llm_by_model_name?(unique_model_name) : LLM?
      llms.each do |name, llm|
        llm.models.try &.each do |model|
          if model.name == unique_model_name
            return llm
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
