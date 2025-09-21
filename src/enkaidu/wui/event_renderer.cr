require "../session_renderer"
require "./work"

require "markterm"

module Enkaidu::Server
  module Render
    abstract class Event
      include JSON::Serializable

      use_json_discriminator "type", {
        message:           Message,
        query:             Query,
        llm_text:          LLMText,
        llm_text_fragment: LLMTextFragment,
        llm_tool_call:     LLMToolCall,
      }

      getter type : String
      getter time = Time.local

      def initialize(@type); end
    end

    abstract class Message < Event
      use_json_discriminator "level", {
        info: InfoMessage, warn: WarningMessage, error: ErrorMessage,
        success: SuccessMessage,
      }

      getter level : String
      getter message : String
      getter? markdown : Bool
      getter details : String?

      def initialize(@level, @message, @details, @markdown)
        super("message")
      end
    end

    class Query < Event
      getter prompt : String

      def initialize(@prompt)
        super("query")
      end
    end

    class InfoMessage < Message
      def initialize(message, details = nil, markdown = false)
        super("info", message, details, markdown)
      end
    end

    class WarningMessage < Message
      def initialize(@message, @details = nil, @markdown = false)
        super("warn", message, details, markdown)
      end
    end

    class ErrorMessage < Message
      def initialize(@message, @details = nil, @markdown = false)
        super("error", message, details, markdown)
      end
    end

    class SuccessMessage < Message
      def initialize(@message, @details = nil, @markdown = false)
        super("success", message, details, markdown)
      end
    end

    class LLMToolCall < Event
      getter name : String
      getter args : String

      def initialize(@name, @args)
        super("llm_tool_call")
      end
    end

    class LLMTextFragment < Event
      getter fragment : String

      def initialize(@fragment)
        super("llm_text_fragment")
      end
    end

    class LLMText < Event
      getter content : String

      def initialize(@content)
        super("llm_text")
      end
    end
  end

  # This class is responsible for rendering console outputs into a queue
  # for retrieval by API
  class EventRenderer < SessionRenderer
    private getter queue = Deque(Render::Event).new

    property? streaming = false
    private getter work_channel : Channel(Work)

    def initialize(@work_channel); end

    private def post_event(event)
      queue.push(event)
      work_channel.send(Work::RenderEventPosted)
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
      puts "  CONFIRM: The assistant wants to run the following command:\n"
      puts "  > #{command}\n\n".colorize(:red).bold
      print "  Allow? [y/N] "
      response = STDIN.raw &.read_char
      puts response

      ['y', 'Y'].includes?(response)
    end

    LLM_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def llm_tool_call(name, args)
      # print "  CALL".colorize(:green)
      # puts " #{name.colorize(:red)} " \
      #      "with #{trim_text(args.to_s, LLM_MAX_TOOL_CALL_ARGS_LENGTH).colorize(:red)}"
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
      # puts "  MCP CALLING \"#{name}\" at server #{uri}.".colorize(:yellow)
      # puts "      with: #{trim_text(args.to_s, MCP_MAX_TOOL_CALL_ARGS_LENGTH)}".colorize(:yellow)
    end

    MCP_MAX_TOOL_RESULT_LENGTH = 72

    def mcp_calling_tool_result(uri, name, result)
      post_event Render::SuccessMessage.new(
        "MCP call \"#{name}\" RESULT:",
        details: "`#{result}`", markdown: true)
      # puts "  MCP CALL (#{name}) RESULT: #{trim_text(result.to_s, MCP_MAX_TOOL_RESULT_LENGTH)}".colorize(:green)
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
