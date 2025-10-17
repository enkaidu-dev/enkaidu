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

    private getter opts : SessionOptions
    private getter connection : LLM::Connection
    private getter chat : LLM::Chat

    private getter mcp_functions = [] of MCPFunction
    private getter mcp_prompts = [] of MCPPrompt
    private getter mcp_connections = [] of MCPC::HttpConnection

    private getter template_prompts = [] of TemplatePrompt
    private getter prompts_by_name = {} of String => MCPPrompt | TemplatePrompt

    private getter loaded_toolsets = {} of String => Tools::ToolSet

    include Session::Toolsets
    include Session::Lifecycle
    include Session::AutoLoad
    include Session::Prompts
    include Session::McpServers

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
      return from_env unless from_config = opts.config.try(&.session).try(&.system_prompt)

      renderer.info_with("INFO: Using system prompt from config file; #{from_config.size} characters")
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
      case r["type"]
      when "tool_call"
        yield r["content"] # tool call
        renderer.llm_tool_call(
          name: r["content"].dig("function", "name").as_s,
          args: r["content"].dig("function", "arguments"))
      when "text"
        renderer.llm_text(r["content"].as_s)
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
    def re_ask
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      chat.re_ask do |event|
        m_process_and_record_ask_event(event)
      end
      consume_tool_calls(tools, ix)
      recorder << "]"
    end

    # Query LLM using a prompt and optional attachments
    def ask(query, attach : LLM::ChatInclusions? = nil, render_query = false)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      renderer.user_query_text(query) if render_query
      chat.ask query, attach do |event|
        m_process_and_record_ask_event(event)
      end
      consume_tool_calls(tools, ix)
      recorder << "]"
    end
  end
end
