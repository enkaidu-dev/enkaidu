require "option_parser"

require "../session_options"

module Enkaidu::CLI
  class Options < SessionOptions
    getter provider_name : String? = nil
    getter model_name : String? = nil
    getter? debug = false
    getter? stream = false
    getter? enable_shell_command = true
    getter recorder_file : IO? = nil
    getter renderer : SessionRenderer

    def initialize(@renderer)
      @opts = OptionParser.parse do |parser|
        parser.banner = "Usage: #{PROGRAM_NAME} [arguments]\n\nOptions"
        parser.on("-p NAME", "--provider=NAME", "The name of the provider: azure_openai, openai, or ollama") { |name| @provider_name = name }
        parser.on("-m NAME", "--model=NAME", "Some providers require a model.") { |name| @model_name = name }
        parser.on("-S", "--streaming", "Enable streaming mode") { @stream = true }
        parser.on("-R FILEPATH", "--recorder-file=FILEPATH", "Record chat processing events to a JSON file") do |path|
          @recorder_file = File.open(path, "w")
        rescue ex
          error_and_exit_with "FATAL: Unable to create recorder file (\"#{path}\"): #{ex.message}", parser
        end
        parser.on("--debug", "Enable debug mode by sending raw responses to the recorder if configure (via -R)") { @debug = true }
        parser.on("--disable-shell-command", "Disable the shell command tool") { @enable_shell_command = false }
        parser.on("--help", "Show this help") do
          puts parser
          exit
        end
        parser.invalid_option do |flag|
          error_and_exit_with "FATAL: #{flag} is not a valid option.", parser
        end
      end

      if provider_name.nil?
        error_and_exit_with "FATAL: Provider required.", help
      elsif provider_name == "ollama" && model_name.nil?
        error_and_exit_with "FATAL: Model required by Ollama provider.", help
      end
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
