require "./enkaidu/*"
require "./enkaidu/cli/*"

require "./sucre/command_parser"

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
    `#{C_USE_MCP} URL [auth_env=ENVARNAME]`
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

    private def handle_use_mcp_command(cmd)
      error = nil
      url = nil
      auth_key = nil
      # Check and extract what we want,
      error = if (url = cmd.arg_at?(1)).nil?
                "ERROR: Specify URL to the MCP server"
              elsif (auth_env = cmd.arg_named?("auth_env")) && (auth_key = ENV[auth_env]?).nil?
                "ERROR: Unable to find environment variable: #{auth_env}."
              end
      # Check if command meets expectation
      unless error || cmd.expect?(C_USE_MCP, String, auth_env: String?)
        error = "ERROR: Unexpected command / parameters"
      end
      # Report error if any
      if error
        renderer.warning_with(error, help: H_C_USE_MCP, markdown: true)
        return
      end
      # All good
      auth_token = MCPC::AuthToken.new(label: "MCP auth token: #{url}", value: auth_key) if auth_key
      session.use_mcp_server url.as(String), auth_token: auth_token
    end

    private def commands(q)
      cmd = CommandParser.new(q)
      case cmd.arg_at?(0)
      when "/bye"
        @done = true
      when "/help"
        renderer.info_with "**The following `/` (slash) commands available.**",
          help: COMMAND_HELP, markdown: true
      when "/use_mcp"
        handle_use_mcp_command(cmd)
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
