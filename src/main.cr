require "./enkaidu/session"
require "./enkaidu/console_renderer"

module Enkaidu
  class Main
    private getter session
    private getter? done = false
    private getter count = 0
    private getter renderer : ConsoleRenderer

    delegate recorder, to: @session

    def initialize
      @renderer = ConsoleRenderer.new
      @session = Session.new(renderer)

      return unless session.streaming?
      puts "WARNING: Markdown formatted rendering is not supported when streaming is enabled (for now). Sorry.\n".colorize(:yellow)
    end

    WELCOME = <<-TEXT
    # Welcome to **Enkaidu**,
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content.

    Furthermore, by connecting with MCP servers Enkaidu can assist you with much more.

    Use `/help` to see the `/` commands available.
    TEXT

    COMMAND_HELP = <<-HELP
    **The following `/` (slash) commands available.**

    `/bye`
      - Exit Enkaidu

    `/help`
      - Shows this information

    `/use_mcp URL`
      - Connect with the specified MCP server and register any available tools
        for use with subsequent queries

    HELP

    private def commands(q)
      case q
      when "/bye"
        @done = true
      when "/help"
        puts Markd.to_term(COMMAND_HELP)
      when .starts_with? "/use_mcp"
        cmd = q.split(' ', 2)
        url = cmd.last.strip
        session.use_mcp_server url
      else
        renderer.warning("ERROR: Unknown command: #{q}")
      end
    end

    private def query(q)
      recorder << "," if count.positive?
      session.ask(query: q)
      @count += 1
      puts
    end

    def run
      puts Markd.to_term(WELCOME)
      recorder << "["
      while !done?
        print "----\nQUERY > ".colorize(:yellow)
        if q = gets
          case q = q.strip
          when .starts_with?("/") then commands(q)
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

Enkaidu::Main.new.run
