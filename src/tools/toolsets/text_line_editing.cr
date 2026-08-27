require "../toolset"
require "./text_line_editing/*"

module Tools
  module TextLineEditing
    toolset = ToolSet.create("TextLineEditing") do
      hold InsertLinesInTextFileTool
      hold ReplaceLinesInTextFileTool
    end
    Tools.register(toolset)
  end
end
