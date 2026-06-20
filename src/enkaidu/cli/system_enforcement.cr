module Enkaidu
  #
  # Enforced system config
  # -----------------------
  #
  # If a system-level config file is found, then Enkaidu ONLY uses that config and does not
  # allow any local config file to override the configuration.
  #
  # - Command line options are supported (except those that modify config file)
  # - Profile folder's macro, prompts, etc are supported (except the config file)
  #
  # This allows someone to offer a shared system with a single admin-managed Enkaidu configuration
  # that prevents the use of local / custom configs that could undo security controls
  #
  @@enforce_system_config = false

  # Return true if a system config file was detected and loaded
  def self.enforce_system_config?
    @@enforce_system_config
  end

  # The system config file location is platform dependent
  {% if flag?(:windows) %}
    ENFORCED_SYS_CONFIG_FILE = Path.new(["C:", "Windows", "System32", "drivers", "etc", "enkaidu.yml"]).to_s
  {% else %}
    ENFORCED_SYS_CONFIG_FILE = "/etc/enkaidu.yml"
  {% end %}

  # Look for the system config file and if present: (a) enable enforcement, and (b)return its path
  protected def self.enforced_system_config_file
    if File.exists?(ENFORCED_SYS_CONFIG_FILE)
      @@enforce_system_config = true
      ENFORCED_SYS_CONFIG_FILE
    end
  end
end
