require "../tools"
require "./file_helper"
require "./file_management/*"

module Tools
  module FileManagement
    toolset = ToolSet.create("FileManagement") do
      hold ListFilesTool
      hold CreateDirectoryTool
      hold RenameFileTool
    end
    Tools.register(toolset)
  end
end
