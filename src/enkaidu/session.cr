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
    private getter connection : LLM::ChatConnection
    private getter chat : LLM::Chat

    private getter mcp_functions = [] of MCPFunction
    private getter mcp_connections = [] of MCPC::HttpConnection

    getter recorder : Recorder
    getter renderer : SessionRenderer

    def initialize(@renderer, @opts)
      @recorder = Recorder.new(opts.recorder_file)

      setup_envs_from_config
      @connection = case opts.provider_type
                    when "openai"       then LLM::OpenAI::ChatConnection.new
                    when "azure_openai" then LLM::AzureOpenAI::ChatConnection.new
                    when "ollama"       then LLM::Ollama::ChatConnection.new
                    else
                      opts.error_and_exit_with "FATAL: Unknown provider type: #{opts.provider_type}", opts.help
                    end

      @chat = connection.new_chat do
        unless (m = opts.model_name).nil?
          with_model m
        end
        with_debug if opts.debug?
        with_streaming if opts.stream?
        with_system_message system_prompt
        with_tool ListFilesTool.new
        with_tool ReadTextFileTool.new
        with_tool CreateTextFileTool.new
        with_tool CreateImageFileTool.new
        with_tool ReplaceTextInTextFileTool.new
        with_tool RenameFileTool.new
        with_tool CreateDirectoryTool.new
        with_tool ShellCommandTool.new(renderer) if opts.enable_shell_command?
      end

      @renderer.streaming = chat.streaming?
    end

    # Load the selected LLM's environment variable values into
    # `ENV`; call this method before initializing an LLM connection
    private def setup_envs_from_config
      if env = opts.config_for_llm.try &.env
        env.each do |name, value|
          ENV[name] = value
        end
      end
    end

    def list_all_tools
      text = String.build do |io|
        chat.each_tool_origin do |origin|
          io << "## " << origin << '\n'
          chat.each_tool(origin: origin) do |tool|
            io << "**" << tool.name << "** "
            io << tool.description << "\n\n"
          end
        end
        io << '\n'
      end
      renderer.info_with("List of available tools.", text, markdown: true)
    end

    private def find_tool_by(name)
      chat.each_tool do |tool|
        return tool if tool.name == name
      end
      nil
    end

    def list_tool_details(tool_name)
      if tool = find_tool_by(tool_name)
        text = String.build do |io|
          io << tool.description << '\n'
          ix = 1
          tool.each_param do |param|
            io << ix << ". `" << param.name << "` : `" << param.type.label << "` " <<
              (param.required? ? "(Required)\n" : "(Optional)\n")
            param.description.split('.').each do |line|
              io << "    * " << line << '\n' unless line.strip.blank?
            end
            ix += 1
          end
        end
        renderer.info_with("Tool details: #{tool_name}", text, markdown: true)
      else
        renderer.info_with("INFO: No such tool available: #{tool_name}")
      end
    end

    private def system_prompt
      ENV.fetch("ENKAIDU_SYSTEM_PROMPT", DEFAULT_SYSTEM_PROMPT)
    end

    private def process_event(r, tools)
      case r["type"]
      when "tool_call"
        tools << r["content"]
        # print "  CALL".colorize(:green)
        # puts " #{r["content"].dig("function", "name").as_s.colorize(:red)} " \
        #      "with #{r["content"].dig("function", "arguments").colorize(:red)}" unless chat.streaming?
        renderer.llm_tool_call(
          name: r["content"].dig("function", "name").as_s,
          args: r["content"].dig("function", "arguments"))
      when "text"
        renderer.llm_text(r["content"].as_s)
        # puts "----".colorize(:green)
        # puts Markd.to_term(r["content"].as_s) unless chat.streaming?
      when .starts_with? "error"
        renderer.llm_error(r["content"])
        # warning("ERROR:\n#{r["content"].to_json}")
      end
    end

    def use_mcp_server(url : String, auth_token : MCPC::AuthToken? = nil)
      mcpc = MCPC::HttpConnection.new(url, tracing: opts.trace_mcp?, auth_token: auth_token)
      # puts "  INIT MCP connection: #{mcpc.uri}".colorize(:green)
      renderer.mcp_initialized(mcpc.uri)
      mcp_connections << mcpc
      if tool_defs = mcpc.list_tools
        tool_defs = tool_defs.as_a
        # puts "  FOUND #{tool_defs.size} tools".colorize(:green)
        renderer.mcp_tools_found(tool_defs.size)
        tool_defs.each do |tool|
          func = MCPFunction.new(tool, mcpc, cli: self)
          mcp_functions << func
          renderer.mcp_tool_ready(func)
          # puts "  ADDED function: #{func.name}".colorize(:green)
          chat.with_tool(func)
        end
      end
    rescue ex
      handle_mcpc_error(ex)
    end

    def handle_mcpc_error(ex)
      renderer.mcp_error(ex)
    end

    def ask(query, render_query = false)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      renderer.user_query(query) if render_query
      chat.ask query do |event|
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
