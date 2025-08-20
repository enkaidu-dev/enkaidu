require "../session_renderer"
require "markterm"

module Enkaidu::CLI
  class ConsoleRenderer < SessionRenderer
    property? streaming = false

    private def prepare_text(help, markdown = false)
      markdown ? Markd.to_term(help.to_s) : help
    end

    def info_with(message, help = nil, markdown = false)
      STDERR.puts message.colorize(:cyan)
      return unless help
      STDERR.puts
      STDERR.puts prepare_text(help, markdown)
    end

    def warning_with(message, help = nil, markdown = false)
      STDERR.puts message.colorize(:light_red)
      return unless help
      STDERR.puts
      STDERR.puts prepare_text(help, markdown)
    end

    def error_with(message, help = nil, markdown = false)
      STDERR.puts message.colorize(:red)
      return unless help
      STDERR.puts
      STDERR.puts prepare_text(help, markdown)
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

    def llm_tool_call(name, args)
      print "  CALL".colorize(:green)
      puts " #{name.colorize(:red)} " \
           "with #{args.colorize(:red)}"
    end

    def llm_error(err)
      warning_with("ERROR:\n#{err.to_json}")
    end

    def llm_text(text, streaming = false)
      if streaming
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

    def mcp_calling_tool(uri, name, args)
      puts "  MCP CALLING \"#{name}\" at server #{uri}.".colorize(:yellow)
      puts "      with: #{args}".colorize(:yellow)
    end

    def mcp_calling_tool_result(uri, name, result)
      suffix = ""
      str = result.to_s
      if str.size > 20
        str = str[..20]
        suffix = "... >8"
      end
      puts "  MCP CALL (#{name}) RESULT: #{str}#{suffix.colorize.mode(:bold)}".colorize(:green)
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
  end
end
