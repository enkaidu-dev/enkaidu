require "../session_renderer"
require "../config"

module Enkaidu::Env
  # Environment folder name that we look for
  DOT_ENKAIDU = ".enkaidu"
  # Current user's HOME directory
  HOME_DIR = Path.home
  # Current directory from which Enkaidu was run
  CURRENT_DIR = Path.new(Dir.current)
  # Supported default config file names
  CONFIG_FILE_NAMES = ["enkaidu.yml", "enkaidu.yaml"]

  alias VarValue = String | Array(String) | Hash(String, String | Array(String))
  alias Variables = Hash(String, VarValue)

  class Profile
    VAR_FILE_NAMES = ["variables.yml", "variables.yaml"]

    # The `SessionRenderer` for this environment
    getter renderer : SessionRenderer
    # The profile DOT_ENKAIDU path if one exists
    getter profile_path : Path?
    # Loaded configuration, if any found
    getter config : Config? = nil
    # Path to loaded configuration, if any found
    getter config_path : Path? = nil
    # Hash of Prompts loaded from `prompts/` folder in the profile
    getter prompts : Hash(String, Config::Prompt)
    # Hash of SystemPrompts loaded from `system_prompts/` folder in the profile
    getter system_prompts : Hash(String, Config::SystemPrompt)
    # Hash of Macros loaded from `macros/` folder in the profile
    getter macros : Hash(String, Config::Macro)

    # Variables loaded from the `variables.*` file
    getter variables : Variables

    # Create a profile using the given base directory where we will look for
    # a DOT_ENKAIDU folder
    def initialize(base_path, @renderer, opt_config_file_path : Path?)
      @profile_path = locate_profile_path(base_path)
      @config = load_config(opt_config_file_path)
      @prompts = load_prompts
      @system_prompts = load_system_prompts
      @macros = load_macros
      @variables = load_variables
    end

    # Find the `DOT_ENKAIDU` directory in the base folder, if any
    private def locate_profile_path(base_path) : Path?
      path = Path.new(base_path, DOT_ENKAIDU)
      return path if Dir.exists?(path)
    end

    private def load_variables
      vars = Variables.new
      if dir = profile_path
        VAR_FILE_NAMES.each do |file|
          path = Path.new(dir, file)
          if File.exists?(path)
            vars.merge! Variables.from_yaml(File.read(path))
          end
        end
      end
      vars
    end

    # Read and parse config file, or fail with exceptions
    private def parse_config_file(file) : Config
      text = File.read(file)
      config = Config.parse(text, file.basename)
      renderer.info_with "INFO: Reading config file: ./#{file.relative_to?(CURRENT_DIR)}"
      @config_path = file
      config
    end

    # Find and load config file, starting with the specific path and then the current one and then the profile directory
    private def load_config(opt_config_file_path) : Config?
      file = opt_config_file_path ||
             find_config_file(CURRENT_DIR) ||
             ((dir = profile_path) && find_config_file(dir))
      return nil unless file
      parse_config_file(file)
    rescue IO::Error
      # If we fail to find default config file, it's OK.
      if opt_config_file_path
        # Only a problem if user specified one
        error_and_exit_with "FATAL: Failed to open config file: #{opt_config_file_path}"
      end
    rescue ex : Config::TooManyDefaultFiles | Config::UnknownFileFormat
      error_and_exit_with "FATAL: #{ex}"
    rescue ex : Config::ParseError
      # Config parsing errors are always bad
      error_and_exit_with "FATAL: Error parsing config file: #{file}\n#{ex}"
    end

    # Given a path, look for the supported config file name/extension variants
    private def find_config_file(path : Path) : Path?
      found = [] of Path
      CONFIG_FILE_NAMES.each do |file_name|
        file_path = Path.new(path, file_name)
        found << file_path if File.exists?(file_path)
      end

      raise Config::TooManyDefaultFiles.new(found) if found.size > 1
      found.first?
    end

    # Load YAML files in the `prompts/` folder as `Config::Prompt`
    private def load_prompts
      prompts = {} of String => Config::Prompt
      each_yaml_file_for("prompts") do |file|
        prompt_map = Hash(String, Config::Prompt).from_yaml(File.read(file))
        prompts.merge!(prompt_map)
      end
      prompts
    end

    # Load YAML files in the `system_prompts/` folder as `Config::SystemPrompt`
    private def load_system_prompts
      sys_prompts = {} of String => Config::SystemPrompt
      each_yaml_file_for("system_prompts") do |file|
        prompt_map = Hash(String, Config::SystemPrompt).from_yaml(File.read(file))
        sys_prompts.merge!(prompt_map)
      end
      sys_prompts
    end

    # Load YAML files in the `macros/` folder as `Config::Macro`
    private def load_macros
      macros = {} of String => Config::Macro
      each_yaml_file_for("macros") do |file|
        macro_map = Hash(String, Config::Macro).from_yaml(File.read(file))
        macros.merge!(macro_map)
      end
      macros
    end

    private def each_yaml_file_for(scope, &)
      if dir = profile_path
        path = Path.new(dir, scope)
        if Dir.exists?(path)
          # Sort the file names to ensure override order for entries with
          # the same name is deterministic.
          Dir.new(path).children.sort!.each do |file|
            yield Path.new(path, file) if file.ends_with?(".yaml") || file.ends_with?(".yml")
          end
        end
      end
    end

    def error_and_exit_with(message)
      renderer.error_with(message)
      exit(1)
    end
  end
end
