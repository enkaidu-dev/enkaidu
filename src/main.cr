require "./enkaidu/cli/*"
require "./enkaidu/wui/main"

module Enkaidu
  # `Main` is the entry point for executing the application, managing initialization and execution flow.
  class Main
    private getter opts : CLI::Options
    private getter console : CLI::ConsoleRenderer

    def initialize
      @console = CLI::ConsoleRenderer.new
      @opts = CLI::Options.new(console)
    end

    def run
      if opts.webui?
        WUI::Main.new(opts).run
      else
        CLI::Main.new(opts).run
      end
    end
  end
end

{% unless flag?(:test) %}
  Enkaidu::Main.new.run
{% end %}
