require "../tools"
require "./image_helper"
require "./image_editing/*"

module Tools
  module ImageEditing
    toolset = ToolSet.create("ImageEditing") do
      hold CreateImageFileTool
      hold ReadImageFileTool
    end
    Tools.register(toolset)
  end
end
