require "../session_renderer"
require "markterm"

module Enkaidu::Server
  module Render
    abstract class BaseEvent
      include JSON::Serializable

      use_json_discriminator "type", {
        message:           Message,
        llm_text:          LLMText,
        llm_text_fragment: LLMTextFragment,
        llm_tool_call:     LLMToolCall,
      }

      getter type : String
      getter time = Time.local

      def initialize(@type); end
    end

    abstract class Message < BaseEvent
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

    class LLMToolCall < BaseEvent
      getter name : String
      getter args : String

      def initialize(@name, @args)
        super("llm_tool_call")
      end
    end

    class LLMTextFragment < BaseEvent
      getter fragment : String

      def initialize(@fragment)
        super("llm_text_fragment")
      end
    end

    class LLMText < BaseEvent
      getter content : String

      def initialize(@content)
        super("llm_text")
      end
    end
  end

  # This class is responsible for rendering console outputs into a queue
  # for retrieval by API
  class EventRenderer < SessionRenderer
    private getter queue = Deque(Render::BaseEvent).new

    property? streaming = false

    def event?
      queue.shift?
    end

    def info_with(message, help = nil, markdown = false)
      queue.push Render::InfoMessage.new(message, details: help.to_s, markdown: markdown)
    end

    def warning_with(message, help = nil, markdown = false)
      queue.push Render::WarningMessage.new(message, details: help.to_s, markdown: markdown)
    end

    def error_with(message, help = nil, markdown = false)
      queue.push Render::ErrorMessage.new(message, details: help.to_s, markdown: markdown)
    end

    def show_inclusions(indicators : Array(String))
      STDERR.puts "~~ Unimplemented renderer #show_inclusions"
      # if indicators.present?
      #   puts "----[ #{indicators.join(" | ")} ]----".colorize.yellow
      # end
    end

    def user_query(query)
      # NOOP
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
      queue.push Render::LLMToolCall.new(name, args.to_s)
    end

    def llm_error(err)
      warning_with("ERROR:\n#{err.to_json}")
    end

    def llm_text(text)
      queue.push(if streaming?
        Render::LLMTextFragment.new(text)
      else
        Render::LLMText.new(text)
      end)
      # if streaming?
      #   print text
      # else
      #   puts Markd.to_term(text)
      # end
    end

    def mcp_initialized(uri)
      STDERR.puts "~~ Unimplemented renderer #mcp_initialized"
      # puts "  INIT MCP connection: #{uri}".colorize(:green)
    end

    def mcp_tools_found(count)
      STDERR.puts "~~ Unimplemented renderer #mcp_tools_found"
      # puts "  FOUND #{count} tools".colorize(:green)
    end

    def mcp_tool_ready(function)
      STDERR.puts "~~ Unimplemented renderer #mcp_tool_ready"
      # puts "  ADDED function: #{function.name}".colorize(:green)
    end

    MCP_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def mcp_calling_tool(uri, name, args)
      STDERR.puts "~~ Unimplemented renderer #mcp_calling_tool"
      # puts "  MCP CALLING \"#{name}\" at server #{uri}.".colorize(:yellow)
      # puts "      with: #{trim_text(args.to_s, MCP_MAX_TOOL_CALL_ARGS_LENGTH)}".colorize(:yellow)
    end

    MCP_MAX_TOOL_RESULT_LENGTH = 72

    def mcp_calling_tool_result(uri, name, result)
      STDERR.puts "~~ Unimplemented renderer #mcp_calling_tool_result"
      # puts "  MCP CALL (#{name}) RESULT: #{trim_text(result.to_s, MCP_MAX_TOOL_RESULT_LENGTH)}".colorize(:green)
    end

    def mcp_error(ex)
      STDERR.puts "~~ Unimplemented renderer #mcp_error"
      # STDERR.puts "ERROR: #{ex.class}: #{ex}".colorize(:red)
      # case ex
      # when MCPC::ResponseError then STDERR.puts(JSON.build(indent: 2) { |builder| ex.details.to_json(builder) })
      # when MCPC::ResultError   then STDERR.puts(JSON.build(indent: 2) { |builder| ex.data.to_json(builder) })
      # else
      #   STDERR.puts ex.inspect_with_backtrace
      # end
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
