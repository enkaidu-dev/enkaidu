require "../toolset"
require "./file_management/*"

module Tools
  module FileManagement
    toolset = ToolSet.create("FileManagement") do
      hold SearchFilesTool
      hold ListFilesTool
      hold FindFilesTool
      hold CreateDirectoryTool
      hold RenameFileTool
      hold DeleteFileTool
    end
    Tools.register(toolset)
  end
end
