require "json"
require "option_parser"
require "markterm"

require "../llm"
require "../tools"

require "./version"
require "./mcp_function"
require "./mcp_prompt"
require "./recorder"
require "./session_options"
require "./session_renderer"
require "./template_prompt"

module Enkaidu
  class InvalidSessionData < Exception; end

  class InvalidSessionQuery < Exception; end

  class About
    include JSON::Serializable
    getter app = "Enkaidu"
    getter ver = VERSION

    protected def initialize; end

    # Singleton instance
    def self.me
      @@about ||= About.new
    end
  end

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
    private getter mcp_prompts = [] of MCPPrompt
    private getter mcp_connections = [] of MCPC::HttpConnection

    private getter template_prompts = [] of TemplatePrompt

    private getter prompts_by_name = {} of String => MCPPrompt | TemplatePrompt

    getter recorder : Recorder
    getter renderer : SessionRenderer

    @loaded_toolsets = {} of String => Tools::ToolSet

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

    private def render_session_event(chat_ev, text_count)
      case chat_ev["type"]
      when "text"
        renderer.llm_text_block(chat_ev["content"].as_s)
        text_count += 1
      when "tool_call"
        text_count = 0
        renderer.llm_tool_call(
          name: chat_ev["content"].dig("function", "name").as_s,
          args: chat_ev["content"].dig("function", "arguments"))
      when "tool_called"
      when "query/text"
        renderer.user_query_text(chat_ev["content"].as_s)
        text_count += 1
      when "query/image_url"
        renderer.user_query_image_url(chat_ev["content"].as_s)
      when "query/file_data"
        renderer.info_with("INCLUDE file: #{chat_ev["content"].as_s}")
      end
      text_count
    end

    private def tail_session_events(num_chats)
      text_count = 0
      @chat.tail_session(num_chats) do |chat_ev|
        text_count = render_session_event chat_ev, text_count
      end
    end

    # Load a session a previously saved session (expects JSONL-format per the `#save_session` method)
    # and render past N chat events (or none by default)
    # last N chats..
    def load_session(io : IO, tail_num_chats = -1)
      # Four lines
      about = JSON.parse(io.gets.as(String))
      raise InvalidSessionData.new("Invalid or missing `about.app`") unless about["app"]? == About.me.app
      raise InvalidSessionData.new("Invalid or missing `about.version`") unless about["ver"]? == About.me.ver

      mcps = NamedTuple(mcp_servers: Array(String)).from_json(io.gets.as(String))
      toolsets = NamedTuple(toolsets: Array(Hash(String, String | Array(String)))).from_json(io.gets.as(String))

      renderer.session_reset
      unload_all_toolsets
      unload_all_mcp_servers
      @chat = setup_chat # new chat BEFORE loading tools, MCP servers

      # load the toolsets
      toolsets[:toolsets].each do |toolset_spec|
        load_toolset_by(
          name: toolset_spec["name"].as(String),
          select_tools: toolset_spec["select"]?.try(&.as(Array(String))))
      end

      # load MCP servers
      mcps[:mcp_servers].each do |config_name|
        use_mcp_by(config_name)
      end

      # load chat session
      sess = io.gets.as(String)
      @chat.load_session(sess)
      tail_session_events(tail_num_chats)
    end

    # Unload everything and start a new session as if we restarted Enkaidu, including auto loading from
    # the configuration
    def reset_session
      renderer.session_reset
      unload_all_toolsets
      unload_all_mcp_servers
      unload_all_prompts
      @chat = setup_chat # new chat BEFORE loading tools, MCP servers
      auto_load
    end

    # Save session to a JSONL file,  where each line in order is as follows:
    #   - about the file / app
    #   - active MCP server connection info
    #   - active toolsets and selected tools
    #   - chat session
    def save_session(io : IO) : Nil
      About.me.to_json(io)
      io.puts

      save_active_mcp_servers(io)
      save_active_toolsets(io)

      chat.save_session(io)
      io.puts
    end

    # Helper to save active MCP server info as a single JSON line
    private def save_active_mcp_servers(io : IO) : Nil
      mcp_server_names = [] of String
      mcp_connections.each do |conn|
        if name = opts.config.try &.find_mcp_server_by_url?(conn.uri.to_s)
          mcp_server_names << name
        else
          renderer.warning_with("WARNING: MCP server not in config cannot be saved with session: #{conn.uri}")
        end
      end
      {mcp_servers: mcp_server_names}.to_json(io)
      io.puts
    end

    # Helper to save active toolsets and their selected tools as a single JSON line
    private def save_active_toolsets(io : IO) : Nil
      toolsets = [] of Hash(String, String | Array(String))
      Tools.each_toolset do |toolset|
        if @loaded_toolsets.has_key?(toolset.name)
          tools = [] of String
          toolset.each_tool_info do |name|
            tools << name if chat.find_tool?(name)
          end
          map = Hash(String, String | Array(String)){
            "name" => toolset.name,
          }
          map["select"] = tools if tools.size < toolset.tool_names.size
          toolsets << map
        end
      end
      {toolsets: toolsets}.to_json(io)
      io.puts
    end

    # Helper to setup the Chat's initial config
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

    private def register_prompt_by_name(name, prompt)
      prompts_by_name[name] = prompt
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

      if prompts = config.prompts
        renderer.info_with("INFO: Auto-loading prompts: #{prompts.keys.join(", ")}")
        auto_load_config_prompts(prompts)
      end
    end

    private def auto_load_config_prompts(prompts)
      prompts.each do |name, prompt|
        tp = TemplatePrompt.new(name, prompt, self)
        template_prompts << tp
        register_prompt_by_name(name, tp)
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

    def list_all_prompts
      text = String.build do |io|
        prompts_by_name.each_value do |prompt|
          # mcp_prompts.each do |prompt|
          io << "**" << prompt.name << "** (" << prompt.origin << "): "
          io << prompt.description << "\n\n"
        end
        io << '\n'
      end
      renderer.info_with("List of available prompts.", text, markdown: true)
    end

    def list_prompt_details(prompt_name)
      if sel_prompt = find_prompt?(prompt_name)
        text = String.build do |io|
          desc = if sel_prompt.description == prompt_name
                   "_No description provided. Using tool name instead._"
                 else
                   sel_prompt.description
                 end
          io << desc << '\n' << '\n'
          if args = sel_prompt.arguments
            io << "### Arguments" << '\n'
            args.each do |arg|
              io << "* `" << arg.name << "`: " << (arg.description || "_(No description)_") << '\n'
            end
            io << '\n'
          end
        end
        renderer.info_with("Prompt details: #{prompt_name} (#{sel_prompt.origin})", text, markdown: true)
      else
        renderer.info_with("INFO: No such prompt available: #{prompt_name}")
      end
    end

    def find_prompt?(prompt_name)
      prompts_by_name[prompt_name]?
    end

    def use_prompt(prompt_name)
      if prompt = find_prompt?(prompt_name)
        case prompt
        when MCPPrompt
          arg_inputs = renderer.mcp_prompt_ask_input(prompt)
          unless (prompt_result = prompt.call_with(arg_inputs)).nil?
            text_count = 0
            chat.import(prompt_result, emit: true) do |chat_ev|
              text_count = render_session_event chat_ev, text_count
            end
            ask(query: nil, attach: nil)
          end
        when TemplatePrompt
          arg_inputs = renderer.user_prompt_ask_input(prompt)
          prompt_text = prompt.call_with(arg_inputs)
          ask(query: prompt_text, render_query: true)
        end
      end
    rescue ex
      handle_mcpc_error(ex)
    end

    private def unload_all_prompts
      template_prompts.clear
      prompts_by_name.clear
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

    def unload_all_toolsets
      @loaded_toolsets.keys.each do |name|
        unload_toolset_by(name)
      end
    end

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
          io << "### " << toolset.name
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
          io << "### Input Schema (Parameters)\n```json\n"
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

    private macro m_process_and_record_ask_event
          unless event["type"] == "done"
            recorder << "," if ix.positive?
            recorder << event.to_json
            ix += 1
            process_event(event, tools)
          end
    end

    def ask(query, attach : LLM::ChatInclusions? = nil, render_query = false)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      if query.nil? && attach.nil?
        chat.re_ask do |event|
          m_process_and_record_ask_event
        end
      elsif query.is_a? String
        renderer.user_query_text(query) if render_query
        chat.ask query, attach do |event|
          m_process_and_record_ask_event
        end
      else
        raise InvalidSessionQuery.new("Cannot call #ask with nil query unless attach is also nil")
      end
      # deal with any tool calls and subsequent events repeatedly until
      # no more tool calls remain
      until tools.empty?
        calls = tools
        tools = [] of JSON::Any
        ev_count = 0
        chat.call_tools_and_ask calls do |event|
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
