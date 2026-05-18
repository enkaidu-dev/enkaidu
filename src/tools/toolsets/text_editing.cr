require "../toolset"
require "./text_editing/*"

module Tools
  module TextEditing
    toolset = ToolSet.create("TextEditing") do
      hold ReadTextFileTool
      hold WriteTextFileTool
      hold ReplaceTextInTextFileTool
      hold InsertLinesInTextFileTool
      hold ReplaceLinesInTextFileTool
    end
    Tools.register(toolset)
  end
end
