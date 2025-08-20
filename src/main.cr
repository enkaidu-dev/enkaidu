require "./enkaidu/*"
require "./enkaidu/cli/*"

require "option_parser"

module Enkaidu
  class Main
    private getter session
    private getter? done = false
    private getter count = 0
    private getter renderer : CLI::ConsoleRenderer
    private getter reader : CLI::QueryReader

    delegate recorder, to: @session

    def initialize
      @renderer = CLI::ConsoleRenderer.new
      @session = Session.new(renderer, opts: CLI::Options.new(@renderer))
      @reader = CLI::QueryReader.new

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

    C_BYE     = "/use_mcp"
    C_USE_MCP = "/use_mcp"
    C_HELP    = "/help"

    H_C_BYE = <<-HELP1
    `#{C_BYE}`
    - Exit Enkaidu
    HELP1

    H_C_USE_MCP = <<-HELP2
    `#{C_USE_MCP} URL [--auth-env ENVARNAME]`
    - Connect with the specified MCP server and register any available tools
      for use with subsequent queries
    - Optionally specify name of environment variable that contains the
      authentication token if needed.
    HELP2

    H_C_HELP = <<-HELP3
    `#{C_HELP}`
    - Shows this information
    HELP3

    COMMAND_HELP = <<-HELP
    #{H_C_BYE}

    #{H_C_HELP}

    #{H_C_USE_MCP}
    HELP

    private def handle_use_mcp_command(q)
      error = nil
      p_auth_token = nil
      args = Process.parse_arguments_posix(q)
      opts = OptionParser.parse(args) do |op|
        op.banner = "#{C_USE_MCP} URL [options]"
        op.separator "\nOptions"
        op.on("--auth-env=NAME", "Specify the env var with the auth token") do |name|
          unless p_auth_token = ENV[name]?
            error = "ERROR: Unable to find environment variable: #{name}."
          end
        end
        op.invalid_option do |option|
          error = "ERROR: Unknown parameter for #{C_USE_MCP}: #{option}"
        end
      end
      error = "ERROR: Expected #{C_USE_MCP} command." unless args.first == C_USE_MCP
      unless error
        if url = args[1]?
          auth_token = if tmp = p_auth_token
                         MCPC::AuthToken.new(label: "MCP auth token: #{url}", value: tmp)
                       end
          session.use_mcp_server url, auth_token: auth_token
        else
          error = "ERROR: Specify URL to the MCP server"
        end
      end
      renderer.warning_with(error, help: H_C_USE_MCP, markdown: true) if error
    end

    private def commands(q)
      case q
      when "/bye"
        @done = true
      when "/help"
        renderer.info_with "**The following `/` (slash) commands available.**",
          help: COMMAND_HELP, markdown: true
      when .starts_with? "/use_mcp"
        handle_use_mcp_command(q)
      else
        renderer.warning_with("ERROR: Unknown command: #{q}")
      end
    end

    private def query(q)
      recorder << "," if count.positive?
      session.ask(query: q)
      @count += 1
    end

    def run
      renderer.llm_text WELCOME
      recorder << "["
      while !done?
        if q = reader.read_next
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
