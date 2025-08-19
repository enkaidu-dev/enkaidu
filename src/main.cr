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

    private C_USE_MCP = "/use_mcp"

    private def handle_use_mcp_command(q)
      ok = true
      p_url = nil
      p_auth_token = nil
      args = Process.parse_arguments_posix(q)
      opts = OptionParser.parse(args) do |op|
        op.banner = "#{C_USE_MCP} URL [options]"
        op.separator "\nOptions"
        op.on("--auth-env=NAME", "-a NAME", "Specify the env var with the auth token") do |name|
          unless p_auth_token = ENV[name]?
            renderer.warning("ERROR: Unable to find environment variable: #{name}.")
            ok = false
          end
          STDERR.puts "...#{name} = #{p_auth_token}"
        end
        op.invalid_option do |option|
          renderer.warning("ERROR: Unknown parameter for #{C_USE_MCP}: #{option}")
          ok = false
        end
      end
      STDERR.puts "... #{args}"
      if args.first == C_USE_MCP
        p_url = args[1]?
      end

      if ok && (url = p_url)
        session.use_mcp_server url,
          auth_token: p_auth_token.try { |tok| MCPC::AuthToken.new(label: "MCP #{url}", value: tok) }
      else
        renderer.warning("ERROR: Invalid parameters for #{C_USE_MCP}\n#{opts}")
      end
    end

    private def commands(q)
      case q
      when "/bye"
        @done = true
      when "/help"
        puts Markd.to_term(COMMAND_HELP)
      when .starts_with? "/use_mcp"
        handle_use_mcp_command(q)
        # params = extract_args_from(q)
        # url = params["$1"] # expect first arg
        # p_auth_token = nil
        # if auth_env = params["auth_env"]?
        #   if (auth_token = ENV[auth_env]?)
        #     p_auth_token = MCPC::AuthToken.new(label: "MCP #{url}", value: auth_token)
        #   else
        #     renderer.warning("ERROR: Cannot use MCP server; unable to find environment variable: #{auth_env}.")
        #     return
        #   end
        # end
        # session.use_mcp_server url, auth_token: p_auth_token
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
        puts "----".colorize(:yellow)
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
