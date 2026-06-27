require "../toolset"
require "./image_editing/*"

module Tools
  module ImageEditing
    toolset = ToolSet.create("ImageEditing") do
      hold WriteImageFileTool
      hold ReadImageFileTool
    end
    Tools.register(toolset)
  end
end
