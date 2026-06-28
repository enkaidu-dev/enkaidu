require "../toolset"
require "./audio_editing/*"

module Tools
  module AudioEditing
    toolset = ToolSet.create("AudioEditing") do
      hold WriteAudioFileTool
      hold ReadAudioFileTool
    end
    Tools.register(toolset)
  end
end
