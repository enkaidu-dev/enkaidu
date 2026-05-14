require "./event"

module Enkaidu::WUI::Render
  class SystemInfo < Event
    getter host
    getter cwd

    def initialize
      super "system_info"
      @cwd = Dir.current
      @host = System.hostname
    end
  end
end
