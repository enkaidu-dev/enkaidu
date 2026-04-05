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

    WELCOME_MSG = "Welcome to Enkaidu #{VERSION}"
    WELCOME     = <<-TEXT
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content, by enabling LLMs
    and connecting with MCP servers.

    When entering a query,
    - Type `/help` to see the `/` commands available.
    - Press `Alt-Enter` or `Option-Enter` to start multi-line editing.
    TEXT

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

    def initialize(@opts)
      ui = opts.renderer
      ui.info_with WELCOME_MSG, WELCOME, markdown: true
      ui.info_with ""

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
        reader.editor.output.puts "----[ #{commander.query_indicators.join(" | ")} ]----".colorize.yellow
      end
      if schema = commander.response_json_schema
        reader.editor.output.puts "----[ JSON response schema (name: #{schema.name}, strict? #{schema.strict?}) ]----".colorize.yellow
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
