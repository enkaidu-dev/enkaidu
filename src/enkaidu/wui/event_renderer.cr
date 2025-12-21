require "../session_renderer"
require "./work"
require "./render_events/*"

require "markterm"
require "reply"

module Enkaidu::WUI
  alias ConfirmationChannel = Channel(Bool)
  alias InputsChannel = Channel(Hash(String, String))

  # This class is responsible for rendering console outputs into a queue
  # for retrieval by API
  class EventRenderer < SessionRenderer
    private getter queue = Deque(Render::Event).new

    # Confirmation requests made to the WUI
    private getter pending_confirmations = Hash(String, ConfirmationChannel).new

    # Input requests made to the WUI
    private getter pending_inputs = Hash(String, InputsChannel).new

    property? streaming = false
    private getter work_channel : Channel(Work)

    def initialize(@work_channel); end

    private def post_event(event)
      queue_size_before_post = queue.size
      queue.push(event)
      # Only signal channel if first event
      work_channel.send(Work::RenderEventPosted) if queue_size_before_post.zero?
    end

    def event?
      queue.shift?
    end

    def info_with(message, help = nil, markdown = false)
      post_event Render::InfoMessage.new(message, details: help.to_s, markdown: markdown)
    end

    def warning_with(message, help = nil, markdown = false)
      post_event Render::WarningMessage.new(message, details: help.to_s, markdown: markdown)
    end

    def error_with(message, help = nil, markdown = false)
      post_event Render::ErrorMessage.new(message, details: help.to_s, markdown: markdown)
    end

    def time_elapsed(duration : Time::Span, label : String? = nil)
      info_with("#{label}#{duration.total_seconds}s elapsed.")
    end

    def user_query_text(query, via_macro = false)
      post_event Render::Query.new(Render::ContentType::Text, query, via_macro)
    end

    def user_query_image_url(url)
      post_event Render::Query.new(Render::ContentType::ImageUrl, url)
    end

    def user_confirm_shell_command?(command)
      confirmation_id = Random::Secure.hex(16)
      confirmation_channel = Channel(Bool).new
      pending_confirmations[confirmation_id] = confirmation_channel

      post_event Render::ShellConfirmation.new(command, confirmation_id)

      # Wait for the response
      result = confirmation_channel.receive
      pending_confirmations.delete(confirmation_id)
      result
    end

    def session_reset
      post_event Render::SessionReset.new
    end

    def session_pushed(depth, keep_tools, keep_prompts, keep_history)
      post_event Render::SuccessMessage.new("SESSION PUSHED (#{depth}) #{keep_history ? "with" : "without"} session history")
    end

    def session_popped(depth)
      post_event Render::SuccessMessage.new("SESSION POPPED (#{depth})")
    end

    # Server handler calls to provide response to a pending confirmation request
    def respond_to_confirmation(confirmation_id : String, approved : Bool)
      if channel = pending_confirmations[confirmation_id]?
        channel.send(approved)
      end
    end

    LLM_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def llm_tool_call(name, args)
      post_event Render::LLMToolCall.new(name, args.to_s)
    end

    def llm_error(err)
      warning_with("ERROR:\n#{err.to_json}")
    end

    def llm_text(text, reasoning : Bool)
      if streaming?
        post_event Render::LLMTextFragment.new(text, reasoning: reasoning)
      else
        llm_text_block(text, reasoning: reasoning)
      end
    end

    def llm_text_block(text, reasoning : Bool)
      post_event Render::LLMText.new(text, reasoning: reasoning)
    end

    def llm_image_url(url)
      post_event Render::LLMImageUrl.new(url)
    end

    def mcp_initialized(uri)
      post_event Render::SuccessMessage.new("MCP connection: #{uri}")
    end

    def mcp_tools_found(count)
      post_event Render::SuccessMessage.new("MCP found #{count} tools")
    end

    def mcp_tool_ready(function)
      post_event Render::SuccessMessage.new("MCP added function: #{function.name}")
    end

    def mcp_prompts_found(count)
      post_event Render::SuccessMessage.new("MCP found #{count} prompts")
    end

    def mcp_prompt_ready(prompt)
      post_event Render::SuccessMessage.new("MCP found prompt: #{prompt.name}")
    end

    def mcp_prompt_ask_input(prompt : MCPPrompt) : Hash(String, String)
      return {} of String => String unless (args = prompt.arguments) && args.size.positive?

      input_id = Random::Secure.hex(16)
      input_channel = InputsChannel.new
      pending_inputs[input_id] = input_channel

      post_event Render::AskForInputs.new(input_id, prompt)

      # Wait for the response
      result = input_channel.receive
      pending_inputs.delete(input_id)
      result
    end

    def user_prompt_ask_input(prompt : TemplatePrompt) : Hash(String, String)
      return {} of String => String unless (args = prompt.arguments) && args.size.positive?

      input_id = Random::Secure.hex(16)
      input_channel = InputsChannel.new
      pending_inputs[input_id] = input_channel

      post_event Render::AskForInputs.new(input_id, prompt)

      # Wait for the response
      result = input_channel.receive
      pending_inputs.delete(input_id)
      result
    end

    # Server handler calls to provide response to a pending confirmation request
    def respond_to_input(input_id : String, inputs : Hash(String, String))
      if channel = pending_inputs[input_id]?
        channel.send(inputs)
      end
    end

    MCP_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def mcp_calling_tool(uri, name, args)
      post_event Render::SuccessMessage.new(
        "MCP calling \"#{name}\" (at #{uri}) with:",
        details: "`#{args}`", markdown: true)
    end

    MCP_MAX_TOOL_RESULT_LENGTH = 72

    def mcp_calling_tool_result(uri, name, result)
      post_event Render::SuccessMessage.new(
        "MCP call \"#{name}\" RESULT:",
        details: "`#{result}`", markdown: true)
    end

    def mcp_error(ex)
      details = case ex
                when MCPC::ResponseError
                  JSON.build(indent: 2) { |builder| ex.details.to_json(builder) }
                when MCPC::ResultError
                  JSON.build(indent: 2) { |builder| ex.data.to_json(builder) }
                else
                  ex.inspect_with_backtrace
                end
      post_event Render::ErrorMessage.new(
        "MCP error: #{ex.class}: #{ex}",
        details: "```\n#{details}\n```", markdown: true)
    end

    private def trim_text(text, max_length)
      suffix = ""
      str = text
      if str.size > max_length
        str = str[..max_length]
        suffix = "... >8"
      end
      "#{str}#{suffix.colorize.mode(:bold)}"
    end
  end
end
