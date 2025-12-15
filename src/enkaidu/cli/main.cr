require "option_parser"

require "./options"
require "./query_reader"
require "./console_renderer"

require "../slash_commander"
require "../session_manager"

module Enkaidu::CLI
  # `Main` is the entry point for executing the application, managing initialization and execution flow.
  class Main
    private getter session_manager : SessionManager
    private getter? done = false
    private getter count = 0
    private getter reader : CLI::QueryReader
    private getter opts : CLI::Options
    private getter commander : Slash::Commander

    delegate session, to: @session_manager

    WELCOME_MSG = "Welcome to Enkaidu #{VERSION}"
    WELCOME     = <<-TEXT
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content, by enabling LLMs
    and connecting with MCP servers.

    When entering a query,
    - Type `/help` to see the `/` commands available.
    - Press `Alt-Enter` or `Option-Enter` to start multi-line editing.
    TEXT

    def initialize(@opts)
      ui = opts.renderer
      ui.info_with WELCOME_MSG, WELCOME, markdown: true
      ui.info_with ""

      @session_manager = SessionManager.new(Session.new(ui, opts: opts))
      @reader = CLI::QueryReader.new(
        input_history_file: opts.config.session.try &.input_history_file)
      @commander = Slash::Commander.new(session_manager)

      return unless session.streaming?
      renderer.warning_with "----\n| SORRY: Markdown formatted rendering is not supported when streaming is enabled (for now).\n----"
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

    private def macro_next?(queue) : String?
      if q = queue.shift?
        renderer.user_query_text(q, via_macro: true)
        return q
      end
      nil
    end

    def run
      session.auto_load
      recorder << "["

      # Queue of queries, appended to when macros are run
      macro_query_queue = [] of String
      while !done?
        show_query_prompt
        if q = macro_next?(macro_query_queue) || reader.read_next
          case q = q.strip
          when .starts_with?("!")
            if mac = session.find_macro_by_name?(q[1..])
              # Expand the macro at the top of the queue, where
              # next query awaits; essentially inserting the macro
              macro_query_queue.insert_all(0, mac.queries)
            else
              renderer.warning_with("Unknown macro: #{q}")
            end
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
