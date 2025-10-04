require "../session_renderer"
require "./work"
require "./render_events/*"

require "markterm"
require "reply"

module Enkaidu::WUI
  class InputReader < Reply::Reader
    property label : String

    def initialize(@label)
      super()
    end

    def prompt(io : IO, line_number : Int32, color : Bool) : Nil
      q = label.colorize(:cyan) if color
      io << q
    end
  end

  # This class is responsible for rendering console outputs into a queue
  # for retrieval by API
  class EventRenderer < SessionRenderer
    private getter queue = Deque(Render::Event).new
    private getter pending_confirmations = Hash(String, Channel(Bool)).new
    private getter input = InputReader.new("> ")

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

    def user_query_text(query)
      post_event Render::Query.new(Render::ContentType::Text, query)
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

    def llm_text(text)
      if streaming?
        post_event Render::LLMTextFragment.new(text)
      else
        llm_text_block(text)
      end
    end

    def llm_text_block(text)
      post_event Render::LLMText.new(text)
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

    private def ask_param_input(name, description)
      text = if description
               "    #{name} [#{description}] :"
             else
               "    #{name} : "
             end
      puts text.colorize(:cyan)
      input.label = "    > "
      input.read_next
    end

    def mcp_prompt_ask_input(prompt) : Hash(String, String)
      warning_with "WARN: Parameter input not yet supported here; see Enkaidu terminal for input."

      text = <<-PREFIX
          #{prompt.description}

      PREFIX
      puts text.colorize(:cyan)

      arg_inputs = {} of String => String
      prompt.arguments.try &.each do |arg|
        unless (value = ask_param_input(arg.name, arg.description)).nil?
          arg_inputs[arg.name] = value
        end
      end
      puts
      arg_inputs
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
