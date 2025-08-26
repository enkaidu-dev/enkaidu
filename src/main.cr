require "./enkaidu/*"
require "./enkaidu/cli/*"

require "./sucre/command_parser"

require "option_parser"

module Enkaidu
  # `Main` is the entry point for executing the application, managing initialization and execution flow.
  class Main
    class ArgumentError < Exception; end

    private getter session
    private getter? done = false
    private getter count = 0
    private getter renderer : CLI::ConsoleRenderer
    private getter reader : CLI::QueryReader
    private getter opts : CLI::Options

    delegate recorder, to: @session

    def initialize
      @renderer = CLI::ConsoleRenderer.new
      @opts = CLI::Options.new(@renderer)
      @session = Session.new(renderer, opts: opts)
      @reader = CLI::QueryReader.new(
        input_history_file: opts.config.try &.session.try &.input_history_file)

      return unless session.streaming?
      puts "WARNING: Markdown formatted rendering is not supported when streaming is enabled (for now). Sorry.\n".colorize(:yellow)
    end

    WELCOME_MSG = "Welcome to Enkaidu"
    WELCOME     = <<-TEXT
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content, by enabling LLMs
    and connecting with MCP servers.

    When entering a query,
    - Type `/help` to see the `/` commands available.
    - Press `Alt-Enter` or `Option-Enter` to start multi-line editing.
    TEXT

    C_BYE     = "/bye"
    C_USE_MCP = "/use_mcp"
    C_TOOL    = "/tool"
    C_HELP    = "/help"

    H_C_TOOL = <<-HELP1
    `#{C_TOOL}` [sub-command]
    - `ls`
      - List all available tools
    - `info TOOLNAME`
      - Provide details about one tool
    HELP1

    H_C_BYE = <<-HELP1
    `#{C_BYE}`
    - Exit Enkaidu
    HELP1

    H_C_USE_MCP = <<-HELP2
    `#{C_USE_MCP} URL [auth_env=ENVARNAME] [transport=auto|legacy|http]`
    - Connect with the specified MCP server and register any available tools
      for use with subsequent queries
    - Optionally specify name of environment variable that contains the
      authentication token if needed.
    - Optionally specify the transport type; defaults to `auto`
    HELP2

    H_C_HELP = <<-HELP3
    `#{C_HELP}`
    - Shows this information
    HELP3

    COMMAND_HELP = <<-HELP
    #{H_C_BYE}

    #{H_C_HELP}

    #{H_C_TOOL}

    #{H_C_USE_MCP}
    HELP

    private def handle_use_mcp_command(cmd)
      # Check if command meets expectation
      if cmd.expect?(C_USE_MCP, String)
        first_arg = cmd.arg_at?(1)
        raise ArgumentError.new("No MCP server URL or name given.") if first_arg.nil?

        uri = URI.parse(first_arg)
        if uri.scheme.nil?
          handle_use_mcp_with_name(first_arg)
        else
          handle_use_mcp_with_url(cmd)
        end
      elsif cmd.expect?(C_USE_MCP, String, auth_env: String?, transport: ["auto", "legacy", "http", nil])
        handle_use_mcp_with_url(cmd)
      else
        raise ArgumentError.new("ERROR: Unexpected command / parameters")
      end
    rescue e : ArgumentError
      renderer.warning_with(e.message, help: H_C_USE_MCP, markdown: true)
    end

    private def handle_use_mcp_with_name(name)
      auth_token = nil
      type = MCPC::TransportType::AutoDetect

      if (config = opts.config).nil?
        raise ArgumentError.new("'#{C_USE_MCP}' with a non-URL argument requires MCP servers to be defined in config.")
      end

      mcp_server = config.mcp_servers[name]
      raise ArgumentError.new("MCP server '#{name}' is not defined in the config file.") if mcp_server.nil?

      url = mcp_server.url
      auth_token = auth_token_for_bearer_token(url, mcp_server.bearer_auth_token)
      transport_type = MCPC::TransportType.from(mcp_server.transport)
      session.use_mcp_server(mcp_server.url, auth_token: auth_token, transport_type: transport_type)
    end

    private def handle_use_mcp_with_url(cmd)
      auth_key = nil
      type = MCPC::TransportType::AutoDetect

      # Check and extract what we want,
      error = if (url = cmd.arg_at?(1)).nil?
                "ERROR: Specify URL to the MCP server"
              elsif (auth_env = cmd.arg_named?("auth_env")) && (auth_key = ENV[auth_env]?).nil?
                "ERROR: Unable to find environment variable: #{auth_env}."
              end

      if transport_arg = cmd.arg_named?("transport")
        type = MCPC::TransportType.from(transport_arg)
      end
      auth_token = auth_token_for_bearer_token(url, auth_key)
      session.use_mcp_server url.as(String), auth_token: auth_token, transport_type: type
    end

    private def auth_token_for_bearer_token(url, bearer_token)
      return if bearer_token.nil?

      MCPC::AuthToken.new(label: "MCP auth token: #{url}", value: bearer_token)
    end

    private def handle_tool_command(cmd)
      if cmd.expect?(C_TOOL, "ls")
        session.list_all_tools
      elsif cmd.expect?(C_TOOL, "info", String)
        session.list_tool_details((cmd.arg_at? 2).as(String))
      else
        renderer.warning_with("ERROR: Unknown or incomplete sub-command", help: H_C_TOOL, markdown: true)
      end
    end

    private def commands(q)
      cmd = CommandParser.new(q)
      case cmd.arg_at?(0)
      when C_BYE
        @done = true
      when C_HELP
        renderer.info_with "The following `/` (slash) commands available:",
          help: COMMAND_HELP, markdown: true
      when C_TOOL
        handle_tool_command(cmd)
      when C_USE_MCP
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
      renderer.info_with WELCOME_MSG, WELCOME, markdown: true
      session.auto_load

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
