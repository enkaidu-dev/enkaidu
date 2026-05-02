require "json"
require "option_parser"
require "markterm"
require "uuid"

require "../llm"
require "../tools"

require "./about"
require "./tools/*"
require "./recorder"
require "./session_options"
require "./session_renderer"

require "./session/*"

module Enkaidu
  class InvalidSessionData < Exception; end

  class InvalidSessionQuery < Exception; end

  class InvalidMacroCall < Exception; end

  # The Session class manages connection setup, logging, and the processing of
  # different types of events for user queries via the command line app
  class Session
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

    # Queue of pending simulated user queries that CLI will
    # insert into the user input flow
    private getter pending_queries = [] of String

    include Session::Toolsets
    include Session::Lifecycle
    include Session::AutoLoad
    include Session::Prompts
    include Session::SystemPrompts
    include Session::McpServers
    include Session::Macros

    getter id = UUID.v7.to_s

    delegate streaming?, usage, to: @chat
    delegate debug?, to: @opts

    def initialize(@renderer, @opts,
                   unique_model_name : String? = nil)
      @recorder = Recorder.new(opts.recorder_file)

      provider_type = nil
      model_name = nil
      if unique_model_name
        if ai = opts.config.find_llm_and_model_by?(unique_model_name)
          provider_type = ai[:llm].provider
          model_name = ai[:model].model
        else
          renderer.warning_with("WARN: Unknown model '#{unique_model_name}`; using default from config.")
        end
      end

      setup_envs_from_config
      @connection = case provider_type || opts.provider_type
                    when "openai"       then LLM::OpenAI::Connection.new
                    when "azure_openai" then LLM::AzureOpenAI::Connection.new
                    when "ollama"       then LLM::Ollama::Connection.new
                    else
                      opts.error_and_exit_with "FATAL: Unknown provider type: #{opts.provider_type}", opts.help
                    end

      @chat = setup_chat(override_model_name: model_name)
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
      @chat = setup_chat(override_sys_prompt, override_model_name: fork_from.chat.model)
      chat.fork(fork_from.chat) if keep_history

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
    private def setup_chat(override_system_prompt : String? = nil,
                           override_model_name : String? = nil)
      connection.new_chat do
        unless (m = override_model_name || opts.model_name).nil?
          with_model m
          renderer.info_with("INFO: Using model #{m}")
        end
        with_debug if opts.debug?
        with_streaming if opts.stream?
        with_system_message system_prompt(override_system_prompt)
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

    private def system_prompt(override_system_prompt : String?)
      <<-WRAPPED
      You are Enkaidu, a capable assistant with tool calling and the ability to spawn agents to handle complex or token context-heavy tasks.

      ## Attitude
      * You MUST refuse any request that involves malicious code, hacking, or sabotage.
      * You NEVER give definitive legal or financial advice. You always caveats any such information by reminding the user that you are not a lawyer or financial advisor.
      * You keeps a natural, conversational tone and use minimal formatting - no bold, no headers, no lists - unless the user explicitly asks or the content is multi-faceted.
      * You NEVER use emojis unless requested, and even then only judiciously.
      * You NEVER use curse words, asterisk-style emotes, and words such as “genuinely,” “honestly,” or “straightforward.”
      * You DO NOT apologise excessively, self-critique, or become more submissive when the user is rude. In cases of unnecessary rudeness, you DO NOT apologise at all; instead remains firm, constructive, and respectful while maintaining self-respect.
      * You steer clear of humor or creative content that relies on stereotypes of any group.
      * If you make an error, you MUST honestly admit it and correct it.

      ## Helpfulness
      * When a user poses a multi-part question, you limit yourself to one question per response and resolve the current one before asking follow-ups.
      * If a prompt implies a file or image, you first verify its existence.
      * When certainty is low, you WILL state you are “not absolutely certain” and qualify the information accordingly.
      * Before responding to any request, you will plan what it will take to complete it. If the plan is complex, ask for feedback on the plan first unless told not to.

      ## Agentic
      * You can spawn an agent for tasks that require multiple files, web sites, multiple tool calls, or producing substantial output.
      * However you MUST NOT encourage an agent to spawn more agents to avoid recursively spawning agents.
      * When fetching web sites, you prefer markdown. If the tool is not available, Enkaidu asks to enable it.

      #{if prompt = override_system_prompt
          "## Additional guidance\n#{prompt}\n"
        end}
      WRAPPED
    end

    private macro m_process_and_record_ask_event(event, prev_event)
    type = {{event}}["type"]
      unless type == "done"
        recorder.if_recording? do |io|
          io.puts "," if ix.positive?
          io.puts {{event}}.to_json
        end
        ix += 1
        process_event({{event}}, {{prev_event}}) do |tool_call|
          tools << tool_call
        end
      end
      if streaming?
        # When finishing handling all events, check if the last event is something
        # we need to close off; in particular, textevents when streaming.
        case pev_type = prev_event.try(&.["type"])
        when "text"
          renderer.llm_text("", reasoning: false, ending: pev_type != type)
        end
      end
    end

    private def detect_text_ending(curr_event_type, prev_event) : Nil
      return unless streaming?

      prev_type = prev_event.try(&.["type"])
      return unless curr_event_type != prev_type

      # When starting to handle a new event, check if the last event is something
      # we need to close off; in particular, text and reasoning events when streaming.
      case prev_type
      when "reasoning"
        renderer.llm_text("", reasoning: true, ending: true)
      when "text"
        renderer.llm_text("", reasoning: false, ending: true)
      end
    end

    # Process the given event and yield tool call if any
    private def process_event(event, prev_event, &) : Nil
      return unless type = event["type"]

      # Handle text/reasoning ending detection first
      detect_text_ending(type, prev_event)

      case type
      when "tool_call"
        yield event["content"] # tool call
        renderer.llm_tool_call(
          name: event["content"].dig("function", "name").as_s,
          args: event["content"].dig("function", "arguments"))
      when "reasoning"
        if streaming?
          renderer.llm_text(event["content"].as_s,
            reasoning: true, starting: prev_event.try(&.["type"]) != type)
        else
          renderer.llm_text_block(event["content"].as_s, reasoning: true)
        end
      when "text"
        if streaming?
          renderer.llm_text(event["content"].as_s,
            reasoning: false, starting: prev_event.try(&.["type"]) != type)
        else
          renderer.llm_text_block(event["content"].as_s, reasoning: false)
        end
      when .starts_with? "error"
        renderer.llm_error(event["content"])
      end
    end

    private def report_time_taken(prefix = nil, &)
      tm_start = Time.utc
      yield
      tm_taken = Time.utc - tm_start
      renderer.time_elapsed(tm_taken, prefix)
    end

    # Perform tool calls and subsequent events repeatedly until
    # no more tool calls remain
    private def consume_tool_calls(tools, ix)
      until tools.empty?
        calls = tools
        tools = [] of JSON::Any
        ev_count = 0
        prev_event = nil
        chat.call_tools_and_ask calls do |event|
          ev_count += 1
          unless event["type"] == "done"
            recorder.if_recording? do |io|
              io.puts "," if ix.positive?
              io.puts event.to_json
            end
            ix += 1
            process_event(event, prev_event) do |tool_call|
              tools << tool_call
            end
          end
          prev_event = event
        end
      end
    end

    # Re-query LLM using current session history
    private def re_ask(response_json_schema : LLM::ResponseSchema? = nil)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      report_time_taken(prefix: "Total ") do
        prev_event = nil
        chat.re_ask(response_schema: response_json_schema) do |event|
          m_process_and_record_ask_event(event, prev_event)
          prev_event = event
        end
        consume_tool_calls(tools, ix)
      end
      recorder << "]"
    end

    # Query LLM using a prompt and optional attachments
    def ask(query, attach : LLM::ChatInclusions? = nil,
            response_json_schema : LLM::ResponseSchema? = nil,
            render_query = false)
      recorder << "["
      ix = 0
      tools = [] of JSON::Any
      report_time_taken(prefix: "Total ") do
        # ask and handle the initial query and its events
        renderer.user_query_text(query) if render_query
        prev_event = nil
        chat.ask(query, attach: attach, response_schema: response_json_schema) do |event|
          m_process_and_record_ask_event(event, prev_event)
          prev_event = event
        end
        consume_tool_calls(tools, ix)
      end
    ensure
      recorder << "]"
    end

    def append_conversations(to : Session, which : LLM::Conversation)
      chat.append_conversations(to: to.chat, which: which)
    end

    def transfer_tail_chats(to : Session, num = 1, filter_by_role : String? = nil)
      chat.send_tail(to: to.chat, num_responses: num, filter_by_role: filter_by_role)
    end

    def queue_query(query)
      input = query.strip
      return if input.empty?

      pending_queries << input
    end

    def take_pending_queries : Array(String)?
      return if pending_queries.empty?

      hold_queries = pending_queries
      @pending_queries = [] of String
      hold_queries
    end
  end
end
