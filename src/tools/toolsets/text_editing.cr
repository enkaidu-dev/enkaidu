require "../toolset"
require "./text_editing/*"

module Tools
  module TextEditing
    toolset = ToolSet.create("TextEditing") do
      hold ReadTextFileTool
      hold WriteTextFileTool
      hold ReplaceTextInTextFileTool
    end
    Tools.register(toolset)
  end
end
