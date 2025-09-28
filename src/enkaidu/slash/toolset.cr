require "./command"

module Enkaidu::Slash
  class ToolsetCommand < Command
    NAME = "/toolset"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `ls`
      - List all built-in toolsets that can be activated
    - `load <TOOLSET_NAME>`
      - Load all the tools from the named toolset
    - `load <TOOLSET_NAME> select=LIST_TOOL_NAMES
      - Load the selected tools from the named toolset
      - E.g. `/toolset load FileManagement select=[list_files rename_file]`
    - `unload <TOOLSET_NAME>`
      - Unload all the tools from the named toolset
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    def handle(session, cmd : CommandParser)
      if cmd.expect?(NAME, "ls")
        session.list_all_toolsets
      elsif cmd.expect?(NAME, "load", String, select: Array(String)?)
        if name = cmd.arg_at?(2)
          selection = cmd.arg_named?("select").try(&.as(Array(String)))
          session.load_toolset_by(name.as(String), select_tools: selection)
        end
      elsif cmd.expect?(NAME, "unload", String)
        if name = cmd.arg_at?(2)
          session.unload_toolset_by(name)
        end
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end
  end
end
