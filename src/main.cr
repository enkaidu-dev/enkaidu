require "termify"

require "./enkaidu/cli/*"
require "./enkaidu/console/*"
require "./enkaidu/wui/main"

module Enkaidu
  # `Main` is the entry point for executing the application, managing initialization and execution flow.
  class Main
    private getter console : Console::Renderer
    private getter terminal : Termify::TerminalCommon

    def initialize
      @terminal = Termify.terminal
      terminal.setup_console

      @console = Console::Renderer.new
      setup_exit_cleanup
    end

    private def setup_exit_cleanup
      at_exit {
        console.reset
        terminal.restore_console
      }

      Signal::INT.trap do
        exit
      end
    end

    def run
      opts = CLI::Options.new(console)
      console.quiet = opts.quiet?

      if opts.webui?
        WUI::Main.new(opts).run
      else
        CLI::Main.new(opts).run
      end
    rescue ex
      cause = ex.cause
      indent = 1
      details = String.build do |io|
        while cause
          indent.times { io << "  " }
          io << "+--"
          io.puts cause.message
          cause = cause.cause
        end
      end
      console.error_with("ERROR: #{ex}", details.empty? ? nil : details)
    end
  end
end

{% unless flag?(:test) %}
  Enkaidu::Main.new.run
{% end %}
