require "../session_renderer"
require "markterm"

module Enkaidu::CLI
  # This class is responsible for rendering console outputs.
  class ConsoleRenderer < SessionRenderer
    property? streaming = false

    private def prepare_text(help, markdown)
      markdown ? Markd.to_term(help.to_s) : help
    end

    private def err_puts_text(help, markdown)
      text = prepare_text(help, markdown)
      STDERR.puts unless text.to_s.starts_with? '\n'
      STDERR.puts text
    end

    def info_with(message, help = nil, markdown = false)
      STDERR.puts message.colorize(:cyan)
      return unless help
      err_puts_text help, markdown
    end

    def warning_with(message, help = nil, markdown = false)
      STDERR.puts message.colorize(:light_red)
      return unless help
      err_puts_text help, markdown
    end

    def error_with(message, help = nil, markdown = false)
      STDERR.puts message.colorize(:red)
      return unless help
      err_puts_text help, markdown
    end

    def user_query(query)
      puts "QUERY".colorize(:yellow)
      puts query
      puts "----".colorize(:green)
    end

    def user_calling_tools
      puts "----".colorize(:green)
    end

    def user_confirm_shell_command?(command)
      puts "  CONFIRM: The assistant wants to run the following command:\n\n"
      puts "  > #{command}\n\n".colorize(:red).bold
      print "  Allow? [y/N] "
      response = STDIN.raw &.read_char
      puts response

      ['y', 'Y'].includes?(response)
    end

    LLM_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def llm_tool_call(name, args)
      print "  CALL".colorize(:green)
      puts " #{name.colorize(:red)} " \
           "with #{trim_text(args.to_s, LLM_MAX_TOOL_CALL_ARGS_LENGTH).colorize(:red)}"
    end

    def llm_error(err)
      warning_with("ERROR:\n#{err.to_json}")
    end

    def llm_text(text)
      if streaming?
        print text
      else
        puts Markd.to_term(text)
      end
    end

    def mcp_initialized(uri)
      puts "  INIT MCP connection: #{uri}".colorize(:green)
    end

    def mcp_tools_found(count)
      puts "  FOUND #{count} tools".colorize(:green)
    end

    def mcp_tool_ready(function)
      puts "  ADDED function: #{function.name}".colorize(:green)
    end

    MCP_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def mcp_calling_tool(uri, name, args)
      puts "  MCP CALLING \"#{name}\" at server #{uri}.".colorize(:yellow)
      puts "      with: #{trim_text(args.to_s, MCP_MAX_TOOL_CALL_ARGS_LENGTH)}".colorize(:yellow)
    end

    MCP_MAX_TOOL_RESULT_LENGTH = 72

    def mcp_calling_tool_result(uri, name, result)
      puts "  MCP CALL (#{name}) RESULT: #{trim_text(result.to_s, MCP_MAX_TOOL_RESULT_LENGTH)}".colorize(:green)
    end

    def mcp_error(ex)
      STDERR.puts "ERROR: #{ex.class}: #{ex}".colorize(:red)
      case ex
      when MCPC::ResponseError then STDERR.puts(JSON.build(indent: 2) { |builder| ex.details.to_json(builder) })
      when MCPC::ResultError   then STDERR.puts(JSON.build(indent: 2) { |builder| ex.data.to_json(builder) })
      else
        STDERR.puts ex.inspect_with_backtrace
      end
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
