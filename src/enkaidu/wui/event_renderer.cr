require "../session_renderer"
require "./work"
require "./render_events/*"

require "markterm"

module Enkaidu::WUI
  # This class is responsible for rendering console outputs into a queue
  # for retrieval by API
  class EventRenderer < SessionRenderer
    private getter queue = Deque(Render::Event).new
    private getter pending_confirmations = Hash(String, Channel(Bool)).new

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

    def show_inclusions(indicators : Array(String))
      STDERR.puts "~~ Unimplemented renderer #show_inclusions"
      # if indicators.present?
      #   puts "----[ #{indicators.join(" | ")} ]----".colorize.yellow
      # end
    end

    def user_query(query)
      post_event Render::Query.new(query)
    end

    def user_calling_tools
      STDERR.puts "~~ Unimplemented renderer #user_calling_tools"
      # puts "----".colorize(:green)
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

    def mcp_initialized(uri)
      post_event Render::SuccessMessage.new("MCP connection: #{uri}")
    end

    def mcp_tools_found(count)
      post_event Render::SuccessMessage.new("MCP found #{count} tools")
    end

    def mcp_tool_ready(function)
      post_event Render::SuccessMessage.new("MCP added function: #{function.name}")
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
