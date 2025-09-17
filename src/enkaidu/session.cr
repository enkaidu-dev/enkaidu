require "option_parser"
require "markterm"

require "../llm"
require "../tools"

require "./mcp_function"
require "./recorder"
require "./session_options"
require "./session_renderer"

module Enkaidu
  # The Session class manages connection setup, logging, and the processing of
  # different types of events for user queries via the command line app
  class Session
    DEFAULT_SYSTEM_PROMPT = "You are a capable coding assistant with " \
                            "the ability to use tool calling to solve " \
                            "complicated multi-step tasks."

    private getter opts : SessionOptions
    private getter connection : LLM::Connection
    private getter chat : LLM::Chat

    private getter mcp_functions = [] of MCPFunction
    private getter mcp_connections = [] of MCPC::HttpConnection

    getter recorder : Recorder
    getter renderer : SessionRenderer

    def initialize(@renderer, @opts)
      @recorder = Recorder.new(opts.recorder_file)

      setup_envs_from_config
      @connection = case opts.provider_type
                    when "openai"       then LLM::OpenAI::Connection.new
                    when "azure_openai" then LLM::AzureOpenAI::Connection.new
                    when "ollama"       then LLM::Ollama::Connection.new
                    else
                      opts.error_and_exit_with "FATAL: Unknown provider type: #{opts.provider_type}", opts.help
                    end

      @chat = setup_chat
      @renderer.streaming = chat.streaming?
    end

    def usage
      chat.usage
    end

    private def setup_chat
      connection.new_chat do
        unless (m = opts.model_name).nil?
          with_model m
          renderer.info_with("INFO: Using model #{model}")
        end
        with_debug if opts.debug?
        with_streaming if opts.stream?
        with_system_message system_prompt
      end
    end

    # Run auto loads specified in the session config
    def auto_load
      return unless config = opts.config

      if auto_load = config.session.try &.auto_load
        if mcp_servers = config.mcp_servers
          if (mcp_server_names = auto_load.mcp_servers) && mcp_server_names.present?
            renderer.info_with("INFO: Auto-loading MCP servers: #{mcp_server_names.join(", ")}")
            auto_load_mcp_servers(mcp_servers, mcp_server_names)
          end
        end

        if (toolsets = auto_load.toolsets) && toolsets.present?
          renderer.info_with("INFO: Auto-loading toolsets: #{toolsets.join(", ")}")
          auto_load_toolsets(toolsets)
        end
      end
    end

    private def auto_load_mcp_servers(mcp_servers, mcp_server_names)
      mcp_server_names.each do |mcp_name|
        mcp_name = mcp_name.strip

        use_mcp_by(mcp_name)
      end
    end

    private def auto_load_toolsets(toolsets)
      toolsets.each do |toolset|
        if toolset.is_a? String
          load_toolset_by(toolset.strip)
        elsif toolset.is_a? NamedTuple
          load_toolset_by(toolset[:name].strip, toolset[:select])
        end
      end
    end

    # Load the selected LLM's environment variable values into
    # `ENV`; call this method before initializing an LLM connection
    private def setup_envs_from_config
      return unless env = opts.config_for_llm.try &.env
      env.each do |name, value|
        ENV[name] = value
      end
    end

    def list_all_tools
      text = String.build do |io|
        chat.each_tool_origin do |origin|
          io << "## " << origin << '\n'
          chat.each_tool(origin: origin) do |tool|
            io << "**" << tool.name << "** : "
            io << tool.description << "\n\n"
          end
        end
        io << '\n'
      end
      renderer.info_with("List of available tools.", text, markdown: true)
    end

    @loaded_toolsets = {} of String => Tools::ToolSet

    def unload_toolset_by(name)
      toolset = Tools[name]?
      if toolset.nil?
        renderer.warning_with("WARNING: No built-in toolset found under the name: #{name}.")
      elsif !@loaded_toolsets.has_key?(name)
        renderer.info_with("INFO: Built-in toolset not loaded: #{name}.")
      else
        message = String.build do |str|
          str << "INFO: Unloaded built-in tools from toolset: "
          ix = 0
          toolset.each_tool_info do |tool_name, _|
            next unless chat.find_tool? tool_name
            str << ", " if ix.positive?
            chat.without_tool(tool_name)
            str << tool_name
            ix += 1
          end
        end
        @loaded_toolsets.delete(name)
        renderer.info_with(message)
      end
    end

    def load_toolset_by(name, select_tools : Enumerable(String)? = nil)
      toolset = Tools[name]?
      if toolset.nil?
        renderer.warning_with("WARNING: No built-in toolset found under the name: #{name}.")
      else
        # Load selected tools or all tools in toolset
        selection = select_tools || toolset.tool_names # select all tool names
        # Filter out tool names in selection that are alreadyloaded
        selection = selection.select { |tool_name| !chat.find_tool?(tool_name) }
        message = if selection && selection.empty?
                    "INFO: Built-in tools in toolset already loaded."
                  else
                    String.build do |str|
                      str << "INFO: Loaded built-in tools from toolset: "
                      ix = 0
                      toolset.produce(renderer, selection: selection) do |tool|
                        str << ", " if ix.positive?
                        chat.with_tool(tool)
                        str << tool.name
                        ix += 1
                      end
                    end
                  end
        @loaded_toolsets[name] = toolset
        renderer.info_with(message)
      end
    end

    def list_all_toolsets
      text = String.build do |io|
        Tools.each_toolset do |toolset|
          loaded = @loaded_toolsets.has_key?(toolset.name)
          io << "## " << toolset.name
          io << (loaded ? " _(Loaded)_\n" : '\n')
          toolset.each_tool_info do |name, description|
            io << "* **" << name << "** : "
            io << description << "\n\n"
          end
        end
        io << '\n'
      end
      renderer.info_with("List of available toolsets.", text, markdown: true)
    end

    def list_tool_details(tool_name)
      if tool = chat.find_tool?(tool_name)
        text = String.build do |io|
          desc = if tool.description == tool_name
                   "_No description provided. Using tool name instead._"
                 else
                   tool.description
                 end
          io << desc << '\n'
          io << "## Input Schema (Parameters)\n```json\n"
          io << JSON.parse(tool.input_json_schema).to_pretty_json
          io << "\n```\n"
        end
        renderer.info_with("Tool details: #{tool_name} (#{tool.origin})", text, markdown: true)
      else
        renderer.info_with("INFO: No such tool available: #{tool_name}")
      end
    end

    private def system_prompt
      from_env = ENV.fetch("ENKAIDU_SYSTEM_PROMPT", DEFAULT_SYSTEM_PROMPT)
      return from_env unless from_config = opts.config.try(&.session).try(&.system_prompt)

      renderer.info_with("INFO: Using system prompt from config file; #{from_config.size} characters")
      from_config
    end

    private def process_event(r, tools)
      case r["type"]
      when "tool_call"
        tools << r["content"]
        renderer.llm_tool_call(
          name: r["content"].dig("function", "name").as_s,
          args: r["content"].dig("function", "arguments"))
      when "text"
        renderer.llm_text(r["content"].as_s)
      when .starts_with? "error"
        renderer.llm_error(r["content"])
      end
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
    rescue ex
      handle_mcpc_error(ex)
    end

    def handle_mcpc_error(ex)
      renderer.mcp_error(ex)
    end

    def ask(query, attach : LLM::Chat::Inclusions? = nil, render_query = false)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      renderer.user_query(query) if render_query
      chat.ask query, attach do |event|
        unless event["type"] == "done"
          recorder << "," if ix.positive?
          recorder << event.to_json
          ix += 1
          process_event(event, tools)
        end
      end
      # deal with any tool calls and subsequent events repeatedly until
      # no more tool calls remain
      until tools.empty?
        calls = tools
        tools = [] of JSON::Any
        ev_count = 0
        chat.call_tools_and_ask calls do |event|
          renderer.user_calling_tools if ev_count.zero?
          ev_count += 1
          unless event["type"] == "done"
            recorder << "," if ix.positive?
            recorder << event.to_json
            ix += 1
            process_event(event, tools)
          end
        end
      end
      recorder << "]"
    end

    delegate streaming?, to: @chat
    delegate debug?, to: @opts
  end
end
