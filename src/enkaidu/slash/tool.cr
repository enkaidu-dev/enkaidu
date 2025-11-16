require "./command"

module Enkaidu::Slash
  class ToolCommand < Command
    NAME = "/tool"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `ls`
      - List all available tools
    - `info <TOOLNAME>`
      - Provide details about one tool
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
        session.list_all_tools
      elsif cmd.expect?(NAME, "info", String)
        session.list_tool_details((cmd.arg_at? 2).as(String))
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end
  end
end
