require "../session_renderer"
require "../config"

module Enkaidu::Env
  # Environment folder name that we look for
  DOT_ENKAIDU = ".enkaidu"
  # Current user's HOME directory
  HOME_DIR = Path.home
  # Current directory from which Enkaidu was run
  CURRENT_DIR = Path.new(Dir.current)

  alias VarValue = String | Array(String) | Hash(String, String | Array(String))
  alias Variables = Hash(String, VarValue)

  class Profile
    CONFIG_FILE_NAME = "config"
    VAR_FILE_NAMES   = ["variables.yml", "variables.yaml"]

    # The `SessionRenderer` for this environment
    getter renderer : SessionRenderer
    # The profile DOT_ENKAIDU path if one exists
    getter profile_path : Path?
    # Loaded profile configuration, if any found
    getter config : ProfileConfig? = nil
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
    def initialize(base_path, @renderer)
      @profile_path = locate_profile_path(base_path)
      @config = load_profile_config
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
    private def parse_config_file(file) : ProfileConfig
      text = File.read(file)
      config = ProfileConfig.from_yaml(text)
      renderer.info_with "INFO: Reading profile config file: ./#{file.relative_to?(CURRENT_DIR)}"
      @config_path = file
      config
    end

    # Find and load config file, starting with the specific path and then the current one and then the profile directory
    private def load_profile_config : ProfileConfig?
      if file = (dir = profile_path) &&
                Config.find_config_file(dir, base_name: CONFIG_FILE_NAME)
        begin
          parse_config_file(file)
        rescue IO::Error
          error_and_exit_with "FATAL: Failed to open profile config file: #{file.relative_to?(CURRENT_DIR)}"
        rescue ex : TooManyDefaultConfigFiles | UnknownConfigFileFormat
          error_and_exit_with "FATAL: #{ex}"
        rescue ex : ConfigParseError
          # Config parsing errors are always bad
          error_and_exit_with "FATAL: Error parsing profile config file: #{file.relative_to?(CURRENT_DIR)}\n#{ex}"
        end
      else
        nil
      end
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

    YAML_EXTS = [".yaml", ".yml"]

    private def each_yaml_file_for(scope : String, &)
      if dir = profile_path
        path = Path.new(dir, scope)
        # Look for and look inside a folder with the name of the scope
        # E.g. `macros/` or `prompts/`
        if Dir.exists?(path)
          each_yaml_file(Dir.new(path)) do |yaml_file|
            yield yaml_file
          end
        end
        # Look for a YAML file with the name of the scope
        # E.g. `macros.yaml` or `prompts.yml`
        found = [] of Path
        YAML_EXTS.each do |suffix|
          path = Path.new(dir, "#{scope}#{suffix}")
          found << path if File.exists?(path)
        end
        error_and_exit_with("FATAL: Only one of these is allowed: #{found}") if found.size > 1
        if path = found.first?
          yield path
        end
      end
    end

    MAX_DIR_DEPTH = 8

    # Recursively yield YAML files in the directory, upto `MAX_DIR_DEPTH`.
    private def each_yaml_file(base_dir : Dir, & : Path ->)
      dirs = [base_dir]

      # Maintain stack of nested directories to avoid recursion
      while current_dir = dirs.pop?
        # Sort the file names to ensure override order for entries with
        # the same name is deterministic.
        current_dir.children.sort!.each do |file|
          path = Path.new(current_dir.path, file)
          if File.directory?(path)
            dirs.push(Dir.new(path))
          elsif File.file?(path)
            yield path if file.ends_with?(".yaml") || file.ends_with?(".yml")
          end
        end
        # Limit depth to avoid chasing symlink loop
        break if dirs.size > MAX_DIR_DEPTH
      end
    end

    def error_and_exit_with(message)
      renderer.error_with(message)
      exit(1)
    end
  end
end
