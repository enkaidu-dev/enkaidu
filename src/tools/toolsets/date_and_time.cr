require "../toolset"
require "./date_and_time/*"

module Tools
  module DateAndTime
    toolset = ToolSet.create("DateAndTime") do
      hold GetCurrentDatetimeTool
    end
    Tools.register(toolset)
  end
end
