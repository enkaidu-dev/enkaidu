require "option_parser"

require "./options"
require "./query_reader"

require "../console"
require "../runtime"

module Enkaidu::CLI
  # `Main` is the entry point for executing the application, managing initialization and execution flow.
  class Main
    private getter? done = false
    private getter count = 0
    private getter reader : QueryReader
    private getter opts : Options
    private getter runtime : Runtime

    {% if flag?(:darwin) %}
      ALT_KEY = "Option"
    {% else %}
      ALT_KEY = "Alt"
    {% end %}

    WELCOME_FIRST_LEFT  = "│ Enkaidu #{VERSION} │ /help for commands │ #{ALT_KEY}-Enter multi-line input │ Tab auto-complete"
    WELCOME_SECOND_LEFT = "│ Welcome to your second-in-command(-line) agentic assistant for AI that YOU control!"
    WELCOME_THIRD_LEFT  = "│ FYI │ Markdown rendering is experimental when streaming."

    WELCOME_WIDTH = [WELCOME_FIRST_LEFT.size, WELCOME_SECOND_LEFT.size, WELCOME_THIRD_LEFT.size].max

    WELCOME_FIRST_RIGHT  = (" " * ((WELCOME_WIDTH - WELCOME_FIRST_LEFT.size) + 2)) + '│'
    WELCOME_SECOND_RIGHT = (" " * ((WELCOME_WIDTH - WELCOME_SECOND_LEFT.size) + 2)) + '│'
    WELCOME_THIRD_RIGHT  = (" " * ((WELCOME_WIDTH - WELCOME_THIRD_LEFT.size) + 2)) + '│'

    WELCOME_FIRST_COLOR = "│ #{"Enkaidu".colorize.bold} #{VERSION} │ " \
                          "#{"/help".colorize(:yellow)} for commands │ #{"#{ALT_KEY}-Enter".colorize(:yellow)} multi-line input │ #{"Tab".colorize(:yellow)} auto-complete"
    WELCOME_THIRD_COLOR = "│ #{"FYI".colorize.bold} │ Markdown rendering is #{"experimental".colorize.bold} when streaming."
    WELCOME_QUIET_BAR   = "─" * (WELCOME_FIRST_LEFT.size + WELCOME_FIRST_RIGHT.size - 2)

    PROMPT_PRERELEASE = "CAUTION! #{VERSION} is a PRE-RELEASE in development.".colorize(:red)

    def quiet?
      opts.quiet?
    end

    private def print_welcome(ui)
      print '┌', WELCOME_QUIET_BAR, '┐', '\n'
      print WELCOME_FIRST_COLOR
      puts WELCOME_FIRST_RIGHT
      unless quiet?
        print '├', WELCOME_QUIET_BAR, '┤', '\n'
        print WELCOME_SECOND_LEFT.colorize.bold
        puts WELCOME_SECOND_RIGHT
      end
      if opts.stream? || opts.config.session.try(&.streaming?)
        print '├', WELCOME_QUIET_BAR, '┤', '\n'
        print WELCOME_THIRD_COLOR.colorize(:yellow).italic
        puts WELCOME_THIRD_RIGHT
      end
      print '└', WELCOME_QUIET_BAR, '┘', '\n'
    end

    def initialize(@opts)
      ui = opts.console
      print_welcome(ui)

      @runtime = Runtime.new(options: opts, renderer: ui)
      @reader = QueryReader.new(
        runtime,
        styler: ui,
        input_history_file: opts.config.session.try &.input_history_file)

      reader.prefix = query_prefix
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

    private def fmt(key : Symbol, text : String) : String
      opts.console.fmt(key, text)
    end

    private def show_query_prompt
      puts
      if PRERELEASE
        puts PROMPT_PRERELEASE
      end
      unless commander.query_indicators.empty?
        puts fmt(:before_query, "────┤ #{commander.query_indicators.join(" | ")} ├────")
      end
      if schema = commander.response_json_schema
        puts fmt(:before_query, "────┤ JSON response schema (name: #{schema.name}, strict? #{schema.strict?}) ├────")
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
