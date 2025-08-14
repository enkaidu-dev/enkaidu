require "./session_renderer"

# Defines configurable options for an Enkaidu session
module Enkaidu
  abstract class SessionOptions
    abstract def provider_name : String?
    abstract def model_name : String?
    abstract def debug?
    abstract def stream?
    abstract def enable_shell_command?
    abstract def recorder_file : IO?
    abstract def renderer : SessionRenderer
  end
end
