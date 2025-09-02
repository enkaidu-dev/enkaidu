require "../toolset"
require "./experimental/*"

module Tools
  module Experimental
    toolset = ToolSet.create("Experimental") do
      hold RegexTextEditTool
      hold PatchTextFileTool
    end
    Tools.register(toolset)
  end
end
