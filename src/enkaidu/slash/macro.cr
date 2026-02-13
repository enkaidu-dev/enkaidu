require "./command"

module Enkaidu::Slash
  class MacroCommand < Command
    NAME = "/macro"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `ls`
      - List all available macros.
      - Macros can be executed by using the `!` sigil before the name of the macro. E.g. `!test`
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.current.session
      if cmd.expect?(NAME, "ls")
        session.list_all_macros
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end
  end
end
