require "./command"

module Enkaidu::Slash
  class SystemPromptCommand < Command
    NAME = "/system_prompt"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `ls`
      - List all available system prompts.
      - System prompts can be selected when using `/session reset`.
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.session
      if cmd.expect?(NAME, "ls")
        session.list_all_system_prompts
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end
  end
end
