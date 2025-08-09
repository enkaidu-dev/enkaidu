require "option_parser"

require "./helpers"

module Enkaidu
  class Options
    include Helpers

    getter provider_name : String? = nil
    getter model_name : String? = nil
    getter? debug = false
    getter? stream = false
    getter log_file : IO? = nil

    def initialize
      @opts = OptionParser.parse do |parser|
        parser.banner = "Usage: #{PROGRAM_NAME} [arguments]\n\nOptions"
        parser.on("-p NAME", "--provider=NAME", "The name of the provider: azure_openai, ollama") { |name| @provider_name = name }
        parser.on("-m NAME", "--model=NAME", "Some providers require a model.") { |name| @model_name = name }
        parser.on("-L FILEPATH", "--log-file=FILEPATH", "Log chat events to log file (JSON)") do |path|
          @log_file = File.open(path, "w")
        rescue ex
          error_with "ERROR: Unable to create log file: #{ex.message}", parser
        end
        parser.on("-D", "--debug", "Enable debug mode") { @debug = true }
        parser.on("-S", "--streaming", "Enable streaming mode") { @stream = true }
        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit
        end
        parser.invalid_option do |flag|
          error_with "ERROR: #{flag} is not a valid option.", parser
        end
      end

      if provider_name.nil?
        error_with "ERROR: Provider required.", help
      elsif provider_name == "ollama" && model_name.nil?
        error_with "ERROR: Model required by Ollama provider.", help
      end
    end

    def help
      @opts.to_s
    end
  end
end
