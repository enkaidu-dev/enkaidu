require "json"
require "option_parser"
require "markterm"

require "../llm"
require "../tools"

require "./about"
require "./mcp_function"
require "./mcp_prompt"
require "./recorder"
require "./session_options"
require "./session_renderer"
require "./template_prompt"

require "./session/*"

module Enkaidu
  class InvalidSessionData < Exception; end

  class InvalidSessionQuery < Exception; end

  # The Session class manages connection setup, logging, and the processing of
  # different types of events for user queries via the command line app
  class Session
    DEFAULT_SYSTEM_PROMPT = "You are a capable coding assistant with " \
                            "the ability to use tool calling to solve " \
                            "complicated multi-step tasks."

    getter recorder : Recorder
    getter renderer : SessionRenderer

    protected getter opts : SessionOptions
    protected getter connection : LLM::Connection
    protected getter chat : LLM::Chat

    protected getter mcp_functions = [] of MCPFunction
    protected getter mcp_prompts = [] of MCPPrompt
    protected getter mcp_connections = [] of MCPC::HttpConnection

    protected getter config_prompts = [] of TemplatePrompt
    protected getter prompts_by_name = {} of String => MCPPrompt | TemplatePrompt

    protected getter system_prompts = {} of String => TemplatePrompt

    protected getter loaded_toolsets = {} of String => Tools::ToolSet

    include Session::Toolsets
    include Session::Lifecycle
    include Session::AutoLoad
    include Session::Prompts
    include Session::SystemPrompts
    include Session::McpServers
    include Session::Macros

    delegate streaming?, usage, to: @chat
    delegate debug?, to: @opts

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

    # Create a new session "forked" from a given `Session` to create a duplicate session.
    def initialize(fork_from : Session, keep_tools = true, keep_prompts = true, keep_history = true, system_prompt_name = nil)
      @recorder = fork_from.recorder
      @opts = fork_from.opts
      @renderer = fork_from.renderer
      @connection = fork_from.connection
      @system_prompts = fork_from.system_prompts.dup

      override_sys_prompt = if system_prompt_name
                              render_system_prompt(system_prompt_name)
                            end
      @chat = setup_chat(override_sys_prompt)
      chat.fork_session(fork_from.chat) if keep_history

      if keep_tools
        @mcp_functions = fork_from.mcp_functions.dup
        @mcp_connections = fork_from.mcp_connections.dup
        @loaded_toolsets = fork_from.loaded_toolsets.dup if keep_tools
        fork_from.chat.each_tool do |tool|
          chat.with_tool tool
        end
      end
      if keep_prompts
        @mcp_prompts = fork_from.mcp_prompts.dup
        @prompts_by_name = fork_from.prompts_by_name.dup
      end
    end

    # Helper to setup the Chat's initial config
    private def setup_chat(override_system_prompt : String? = nil)
      connection.new_chat do
        unless (m = opts.model_name).nil?
          with_model m
          renderer.info_with("INFO: Using model #{model}")
        end
        with_debug if opts.debug?
        with_streaming if opts.stream?
        with_system_message override_system_prompt || system_prompt
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

    private def system_prompt
      from_env = ENV.fetch("ENKAIDU_SYSTEM_PROMPT", DEFAULT_SYSTEM_PROMPT)
      return from_env unless from_config = opts.config.auto_load.try(&.system_prompt)

      renderer.info_with("INFO: Using system prompt from config file; #{from_config.size} characters")
      renderer.warning_with("WARN: The `system_prompt` property in config is deprecated. Use `system_prompt_name` instead.")
      from_config
    end

    private macro m_process_and_record_ask_event(event)
      unless {{event}}["type"] == "done"
        recorder << "," if ix.positive?
        recorder << {{event}}.to_json
        ix += 1
        process_event({{event}}) do |tool_call|
          tools << tool_call
        end
      end
    end

    # Process the given event and yield tool call if any
    private def process_event(r, &)
      case type = r["type"]
      when "tool_call"
        yield r["content"] # tool call
        renderer.llm_tool_call(
          name: r["content"].dig("function", "name").as_s,
          args: r["content"].dig("function", "arguments"))
      when "text", "reasoning"
        if streaming?
          renderer.llm_text(r["content"].as_s, reasoning: type == "reasoning")
        else
          renderer.llm_text_block(r["content"].as_s, reasoning: type == "reasoning")
        end
      when .starts_with? "error"
        renderer.llm_error(r["content"])
      end
    end

    # Perform tool calls and subsequent events repeatedly until
    # no more tool calls remain
    private def consume_tool_calls(tools, ix)
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
            process_event(event) do |tool_call|
              tools << tool_call
            end
          end
        end
      end
    end

    # Re-query LLM using current session history
    def re_ask(response_json_schema : LLM::ResponseSchema? = nil)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      chat.re_ask(response_schema: response_json_schema) do |event|
        m_process_and_record_ask_event(event)
      end
      consume_tool_calls(tools, ix)
      recorder << "]"
    end

    # Query LLM using a prompt and optional attachments
    def ask(query, attach : LLM::ChatInclusions? = nil,
            response_json_schema : LLM::ResponseSchema? = nil,
            render_query = false)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      renderer.user_query_text(query) if render_query
      chat.ask(query, attach: attach, response_schema: response_json_schema) do |event|
        m_process_and_record_ask_event(event)
      end
      consume_tool_calls(tools, ix)
      recorder << "]"
    end

    def transfer_tail_chats(to : Session, num = 1, filter_by_role : String? = nil)
      chat.send_tail_session(to: to.chat, num_responses: num, filter_by_role: filter_by_role)
    end
  end
end
