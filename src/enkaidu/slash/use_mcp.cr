require "./command"

module Enkaidu::Slash
  class UseMcpCommand < Command
    NAME = "/use_mcp"

    HELP = <<-HELP2
    `#{NAME} <NAME>`

    `#{NAME} <URL> [auth_env=<ENVARNAME>] [transport=auto|legacy|http]`
    - Connect with the specified MCP server and register any available tools
      for use with subsequent queries
    - MCP server can be specified with URL or name from the config file
    - When loading with a URL
      - Optionally specify the transport type; defaults to `auto`
      - Optionally specify name of environment variable that contains the
        authentication token if needed.
    HELP2

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.current.session
      begin
        # Check if command meets expectation
        if cmd.expect?(NAME, String)
          first_arg = cmd.arg_at?(1)
          raise ArgumentError.new("No MCP server URL or name given.") if first_arg.nil?

          uri = URI.parse(first_arg.as(String))
          if uri.scheme.nil?
            handle_use_mcp_with_name(session, first_arg.as(String))
          else
            handle_use_mcp_with_url(session, cmd)
          end
        elsif cmd.expect?(NAME, String, auth_env: String?, transport: ["auto", "legacy", "http", nil])
          handle_use_mcp_with_url(session, cmd)
        else
          raise ArgumentError.new("ERROR: Unknown or incomplete sub-command: '#{cmd.input}'")
        end
      rescue e : ArgumentError
        session.renderer.warning_with(e.message || e.class.name, help: HELP, markdown: true)
      end
    end

    private def handle_use_mcp_with_name(session, name)
      session.use_mcp_by(name)
    end

    private def handle_use_mcp_with_url(session, cmd)
      auth_key = nil
      type = MCPC::TransportType::AutoDetect

      raise ArgumentError.new("ERROR: Specify URL to the MCP server") if (url = cmd.arg_at?(1)).nil?
      if (auth_env = cmd.arg_named?("auth_env").try(&.as(String))) && (auth_key = ENV[auth_env]?).nil?
        raise ArgumentError.new("ERROR: Unable to find environment variable: #{auth_env}.")
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
  end
end
