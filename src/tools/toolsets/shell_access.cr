require "../toolset"
require "./shell_access/*"

module Tools
  module ShellAccess
    toolset = ToolSet.create("ShellAccess") do
      hold ShellCommandTool
    end
    Tools.register(toolset)
  end
end
