require "option_parser"

require "./enkaidu/*"
require "./enkaidu/cli/*"

require "./sucre/command_parser"
require "./tools/image_helper"

module Enkaidu
  # Read this at compile time from shard.yml one day
  VERSION = "0.1.0"

  # `Main` is the entry point for executing the application, managing initialization and execution flow.
  class Main
    private getter session
    private getter? done = false
    private getter count = 0
    private getter reader : CLI::QueryReader
    private getter opts : CLI::Options
    private getter commander : SlashCommander

    delegate recorder, to: @session
    delegate renderer, to: @session

    WELCOME_MSG = "Welcome to Enkaidu"
    WELCOME     = <<-TEXT
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content, by enabling LLMs
    and connecting with MCP servers.

    When entering a query,
    - Type `/help` to see the `/` commands available.
    - Press `Alt-Enter` or `Option-Enter` to start multi-line editing.
    TEXT

    def initialize
      ui = CLI::ConsoleRenderer.new
      ui.info_with WELCOME_MSG, WELCOME, markdown: true
      ui.info_with ""

      @opts = CLI::Options.new(ui)
      @session = Session.new(ui, opts: opts)
      @reader = CLI::QueryReader.new(
        input_history_file: opts.config.try &.session.try &.input_history_file)
      @commander = SlashCommander.new(session)

      return unless session.streaming?
      renderer.warning_with "----\n| SORRY: Markdown formatted rendering is not supported when streaming is enabled (for now).\n----"
    end

    private def query(q)
      recorder << "," if count.positive?
      session.ask(query: q, attach: commander.take_inclusions)
      @count += 1
    end

    def run
      session.auto_load

      recorder << "["
      while !done?
        puts
        renderer.show_inclusions(commander.query_indicators)
        if q = reader.read_next
          case q = q.strip
          when .starts_with?("/")
            @done = commander.make_it_so(q) == :done
          else
            query(q)
          end
        else
          @done = true
        end
      end
      recorder << "]"
    ensure
      recorder.close
    end
  end
end

{% unless flag?(:test) %}
  Enkaidu::Main.new.run
{% end %}
