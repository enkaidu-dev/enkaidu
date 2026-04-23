require "option_parser"

require "./options"
require "./query_reader"
require "./console_renderer"

require "../runtime"

module Enkaidu::CLI
  # `Main` is the entry point for executing the application, managing initialization and execution flow.
  class Main
    private getter? done = false
    private getter count = 0
    private getter reader : CLI::QueryReader
    private getter opts : CLI::Options
    private getter runtime : Runtime

    {% if flag?(:darwin) %}
      ALT_KEY_NAME = "Option"
    {% else %}
      ALT_KEY_NAME = "Alt"
    {% end %}

    WELCOME_PRERELEASE = <<-TEXT
    ┌─── CAUTION ───────────────────────────┐
    │ This is a PRE-RELEASE in development. │
    └───────────────────────────────────────┘
    TEXT

    SORRY_NO_MARKDOWN = <<-TEXT
    ┌─── SORRY ────────────────────────────────────────────────────────────────┐
    │ Markdown formatted rendering is not available when streaming is enabled. │
    └──────────────────────────────────────────────────────────────────────────┘
    TEXT

    WELCOME_FIRST_LEFT   = "│ Enkaidu #{VERSION} │ /help for commands │ #{ALT_KEY_NAME}-Enter for multi-line input"
    WELCOME_SECOND_LEFT  = "│ Welcome to your second-in-command(-line) agentic assistant for using LLMs + MCP."
    WELCOME_WIDTH        = Math.max(WELCOME_FIRST_LEFT.size, WELCOME_SECOND_LEFT.size)
    WELCOME_FIRST_RIGHT  = (" " * ((WELCOME_WIDTH - WELCOME_FIRST_LEFT.size) + 2)) + '│'
    WELCOME_SECOND_RIGHT = (" " * ((WELCOME_WIDTH - WELCOME_SECOND_LEFT.size) + 2)) + '│'
    WELCOME_QUIET_COLOR  = "│ Enkaidu #{VERSION} │ " \
                           "#{"/help".colorize(:yellow)} for commands │ #{"#{ALT_KEY_NAME}-Enter".colorize(:yellow)} for multi-line input"
    WELCOME_QUIET_BAR = "─" * (WELCOME_FIRST_LEFT.size + WELCOME_FIRST_RIGHT.size - 2)

    def quiet?
      opts.quiet?
    end

    private def print_welcome(ui)
      print '┌', WELCOME_QUIET_BAR, '┐', '\n'
      print WELCOME_QUIET_COLOR
      puts WELCOME_FIRST_RIGHT
      unless quiet?
        print '├', WELCOME_QUIET_BAR, '┤', '\n'
        print WELCOME_SECOND_LEFT
        puts WELCOME_SECOND_RIGHT
      end
      print '└', WELCOME_QUIET_BAR, '┘', '\n'
    end

    def initialize(@opts)
      ui = opts.renderer
      print_welcome(ui)

      @runtime = Runtime.new(options: opts, renderer: ui)
      @reader = CLI::QueryReader.new(
        input_history_file: opts.config.session.try &.input_history_file)

      reader.prefix = query_prefix

      if PRERELEASE
        puts WELCOME_PRERELEASE.colorize(:red)
      end

      return unless session.streaming?
      puts SORRY_NO_MARKDOWN.colorize(:yellow)
    end

    private def session_manager
      runtime.session_manager
    end

    private def commander
      runtime.commander
    end

    private def session
      session_manager.current.session
    end

    private def renderer
      session.renderer
    end

    private def recorder
      session.recorder
    end

    private def query(q)
      recorder << "," if count.positive?
      session.ask(query: q,
        attach: commander.take_inclusions!,
        response_json_schema: commander.take_response_schema!)
      @count += 1
    end

    private def show_query_prompt
      puts
      unless commander.query_indicators.empty?
        reader.editor.output.puts "────┤ #{commander.query_indicators.join(" | ")} ├────".colorize.yellow
      end
      if schema = commander.response_json_schema
        reader.editor.output.puts "────┤ JSON response schema (name: #{schema.name}, strict? #{schema.strict?}) ├────".colorize.yellow
      end
    end

    private def query_prefix
      stack = session_manager.current
      depth = stack.depth

      String.build do |str|
        str << '@' << stack.name
        str << ':' << depth if depth > 1
      end
    end

    private def handle_runtime_event(ev)
      case ev
      when Runtime::Event::Done
        @done = true
      when Runtime::Event::SlashCommand
        reader.prefix = query_prefix
      end
    end

    def run
      session.auto_load
      recorder << "["

      while !done?
        show_query_prompt
        if q = reader.read_next
          runtime.execute_query(q) do |runtime_event|
            handle_runtime_event(runtime_event)
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
