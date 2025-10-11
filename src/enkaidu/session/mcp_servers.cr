module Enkaidu
  class Session
    module McpServers
      def unload_all_mcp_servers
        mcp_functions.clear
        mcp_prompts.clear
        mcp_connections.each do |conn|
          renderer.info_with("INFO: MCP server connection unloaded: #{conn.uri}.")
          conn.close
        end
        mcp_connections.clear
      end

      # Use MCP server by config_name, retrieved from Config.
      def use_mcp_by(config_name : String)
        return unless config = opts.config

        mcp_server = config.mcp_servers.try &.[config_name]?
        if mcp_server.nil?
          renderer.warning_with("WARNING: No MCP server found in the config under the name: #{config_name}.")
          return
        end

        url = mcp_server.url
        bearer_token_string = mcp_server.bearer_auth_token
        auth_token = unless bearer_token_string.nil?
          MCPC::AuthToken.new(label: "MCP auth token: #{url}", value: bearer_token_string)
        end
        transport = MCPC::TransportType.from?(mcp_server.transport) || MCPC::TransportType::AutoDetect

        use_mcp_server(url, auth_token: auth_token, transport_type: transport)
      end

      def use_mcp_server(url : String, auth_token : MCPC::AuthToken? = nil, transport_type = MCPC::TransportType::AutoDetect)
        mcpc = MCPC::HttpConnection.new(url, tracing: opts.trace_mcp?,
          auth_token: auth_token, transport_type: transport_type)
        renderer.mcp_initialized(mcpc.uri)
        mcp_connections << mcpc
        if tool_defs = mcpc.list_tools
          tool_defs = tool_defs.as_a
          renderer.mcp_tools_found(tool_defs.size)
          tool_defs.each do |tool|
            func = MCPFunction.new(tool, mcpc, cli: self)
            mcp_functions << func
            renderer.mcp_tool_ready(func)
            chat.with_tool(func)
          end
        end
        if mcpc.supports_prompts? && (prompt_defs = mcpc.list_prompts)
          prompt_defs = prompt_defs.as_a
          renderer.mcp_prompts_found(prompt_defs.size)
          prompt_defs.each do |prompt_spec|
            prompt = MCPPrompt.new(prompt_spec, mcpc, cli: self)
            mcp_prompts << prompt
            renderer.mcp_prompt_ready(prompt)
            register_prompt_by_name(prompt.name, prompt)
          end
        end
      rescue ex
        handle_mcpc_error(ex)
      end

      def handle_mcpc_error(ex)
        renderer.mcp_error(ex)
      end
    end
  end
end
