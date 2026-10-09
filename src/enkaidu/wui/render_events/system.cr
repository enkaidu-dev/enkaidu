require "./event"

module Enkaidu::WUI::Render
  class SystemInfo < Event
    getter host
    getter cwd
    getter macros : MacroProcessingHelper::AllMacros

    def initialize(runtime : Runtime)
      super "system_info"
      @cwd = Dir.current
      @host = System.hostname
      @macros = runtime.macros.all_macros
    end
  end
end
