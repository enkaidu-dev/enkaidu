require "./session_renderer"
require "./config"

module Enkaidu
  # Defines configurable options for an Enkaidu session
  abstract class SessionOptions
    abstract def provider_type : String?
    abstract def model_name : String?
    abstract def debug?
    abstract def stream?
    abstract def enable_shell_command?
    abstract def recorder_file : IO?
    abstract def renderer : SessionRenderer

    abstract def config_for_llm : Config::LLM?
  end
end
