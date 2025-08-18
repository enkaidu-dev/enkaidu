require "./session_renderer"
require "./config"

# Defines configurable options for an Enkaidu session
module Enkaidu
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
