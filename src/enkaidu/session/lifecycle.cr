module Enkaidu
  # The Session class manages connection setup, logging, and the processing of
  # different types of events for user queries via the command line app
  class Session
    module Lifecycle
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
      # the configuration; use given system prompt name if any
      def reset_session(sys_prompt : String?)
        renderer.session_reset
        unload_all_toolsets
        unload_all_mcp_servers
        unload_all_prompts

        override_sys_prompt = if sys_prompt
                                render_system_prompt(sys_prompt)
                              end
        @chat = setup_chat(override_sys_prompt)

        # new chat BEFORE loading tools, MCP servers
        auto_load_essentials(opts.config)
        unless override_sys_prompt
          check_and_set_system_prompt(opts.config)
        end
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
          if name = opts.config.find_mcp_server_by_url?(conn.uri.to_s)
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

      private def render_session_event(chat_ev, text_count)
        case chat_ev["type"]
        when "text"
          renderer.llm_text_block(chat_ev["content"].as_s, reasoning: false)
          text_count += 1
        when "reasoning"
          renderer.llm_text_block(chat_ev["content"].as_s, reasoning: true)
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
    end
  end
end
