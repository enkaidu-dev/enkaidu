require "../toolset"
require "./web/*"

module Tools
  module Web
    toolset = ToolSet.create("Web") do
      hold HttpGetTextTool
    end
    Tools.register(toolset)
  end
end
