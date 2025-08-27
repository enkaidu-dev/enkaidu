require "../tools"
require "./file_helper"
require "./text_editing/*"

module Tools
  module TextEditing
    toolset = ToolSet.create("TextEditing") do
      hold ReadTextFileTool
      hold CreateTextFileTool
      hold RegexTextEditTool
      hold ReplaceTextInTextFileTool
    end
    Tools.register(toolset)
  end
end
