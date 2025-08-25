require "option_parser"

require "../session_options"
require "../config"

module Enkaidu::CLI
  # This class handles the options for the command-line interface.
  class Options < SessionOptions
    @options = {} of Symbol => String

    getter provider_type : String? = nil
    getter model_name : String? = nil
    getter? debug = false
    getter? stream = false
    getter? trace_mcp = false
    getter? enable_shell_command = true
    getter recorder_file : IO? = nil

    getter config_for_llm : Config::LLM?
    getter config : Config?

    private getter renderer : SessionRenderer

    private def add(name : Symbol, value : String | Bool)
      @options[name] = value.to_s
    end

    def initialize(@renderer)
      @opts = OptionParser.parse do |parser|
        parser.banner = "Usage: #{PROGRAM_NAME} [arguments]"
        define_usage_options(parser)
        define_config_options(parser)
        define_troubleshooting_options(parser)
        parser.invalid_option do |flag|
          error_and_exit_with "FATAL: #{flag} is not a valid option.", parser
        end
      end

      load_config
      check_config_for_defaults
      verify_required_options
    end

    private def define_usage_options(parser)
      parser.separator("\nOPTIONS")
      parser.on("--model=NAME", "-m NAME", "The name of the AI model to use") do |name|
        @model_name = name
        add(:model, name)
      end
      parser.on("--streaming", "-S", "Enable streaming mode") do
        @stream = true
        add(:stream, true)
      end

      parser.separator <<-MODEL

              The model name can be one defined in the config file. Otherwise
              also specify the provider type using the '--provider' option.

      MODEL

      parser.on("--provider=TYPE", "-p TYPE",
        "If needed, one of \"azure_openai\", \"openai\", or \"ollama\".") do |type|
        @provider_type = type
        add(:provider_type, type)
      end

      parser.separator <<-PROVIDER

              If using a provider, different types depend on different environment
              variables.

              ollama        OLLAMA_ENDPOINT (defaults to http://localhost:11434)
              openai        OPENAI_MODEL, OPENAI_API_KEY,
                                    OPENAI_ENDPOINT (defaults to https://api.openai.com)
              azure_openai  AZURE_OPENAI_MODEL, AZURE_OPENAI_ENDPOINT,
                                    AZURE_OPENAI_API_KEY, AZURE_OPENAI_API_VER
      PROVIDER
    end

    private def define_config_options(parser)
      parser.separator("\nCONFIGURE")
      parser.on("--disable-shell-command",
        "Disable the shell command tool") do
        @enable_shell_command = false
        add(:enable_shell_command, false)
      end
      parser.on("--config=FILEPATH", "-C FILEPATH",
        "Config #{Config::FORMATS.join(" or ")} file path; " \
        "defaults to \"#{Config::DEFAULT_NAME}.{#{Config::EXTENSIONS.join('|')}}\"") do |path|
        add(:config_file, path)
      rescue ex
        error_and_exit_with "FATAL: Unable to open file (\"#{path}\"): #{ex.message}", parser
      end
    end

    private def define_troubleshooting_options(parser)
      parser.separator("\nTROUBLESHOOTING")
      parser.on("--recorder-file=FILEPATH", "-R FILEPATH",
        "Record chat processing events to a JSON file") do |path|
        @recorder_file = File.open(path, "w")
        add(:record_to_file, path)
      rescue ex
        error_and_exit_with "FATAL: Unable to create recorder file (\"#{path}\"): #{ex.message}", parser
      end
      parser.on("--debug",
        "Sending raw protocol messages to the recorder configured (via -R)") do
        @debug = true
        add(:debug, true)
      end
      parser.on("--trace-mcp",
        "Enable transport traces for MCP networking") do
        @trace_mcp = true
        add(:trace_mcp, true)
      end
      parser.on("--help", "Show this help") do
        puts parser
        exit
      end
    end

    private def check_config_for_defaults
      # Check config for default options
      if global_opts = (config.try &.global)
        @stream = global_opts.streaming? unless @options.has_key?(:stream)
        @trace_mcp = global_opts.trace_mcp? unless @options.has_key?(:trace_mcp)
        @enable_shell_command = global_opts.enable_shell_command? unless @options.has_key?(:enable_shell_command)
      end

      # Check config for default options
      if session_opts = (config.try &.session)
        @provider_type = session_opts.provider_type if provider_type.nil?
        @model_name = session_opts.model if model_name.nil?
      end

      return unless model_name && provider_type.nil?
      # look up unique model name
      return unless info = (config.try &.find_llm_and_model_by?(unique_model_name: model_name))
      @config_for_llm = info[:llm]
      @provider_type = info[:llm].provider
      @model_name = info[:model].model
    end

    private def verify_required_options
      # Verify required options
      if provider_type.nil?
        error_and_exit_with "FATAL: Provider required.", help
      elsif provider_type == "ollama" && model_name.nil?
        error_and_exit_with "FATAL: Model required by Ollama provider.", help
      end
    end

    private def load_config
      config_file = @options[:config_file]?
      auto_config = config_file.nil?
      config_file = Config.find_default_file unless config_file

      if file = config_file
        renderer.info_with "INFO: Reading config file: #{file}"
        @config = Config.parse(File.read(file), file)
      end
    rescue IO::Error
      # If we fail to find default config file, it's OK.
      unless auto_config
        # Only a problem if user specified one
        error_and_exit_with "FATAL: Failed to open config file: #{file}", help
      end
    rescue ex : Config::TooManyDefaultFiles | Config::UnknownFileFormat
      error_and_exit_with "FATAL: #{ex}", help
    rescue ex : Config::ParseError
      # Config parsing errors are always bad
      error_and_exit_with "FATAL: Error parsing config file: #{file}\n#{ex}", help
    end

    def error_and_exit_with(message, help)
      renderer.error_with(message, help)
      exit(1)
    end

    def help
      @opts.to_s
    end
  end
end
