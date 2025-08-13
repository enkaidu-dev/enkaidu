require "./session_renderer"

module Enkaidu
  class ConsoleRenderer < SessionRenderer
    property? streaming = false

    def warning(message)
      STDERR.puts "***".colorize(:red)
      STDERR.puts message.colorize(:red)
      STDERR.puts
    end

    def error_with(message, help = nil)
      STDERR.puts message.colorize(:red)
      return unless help
      STDERR.puts
      STDERR.puts help
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
      warning("ERROR:\n#{err.to_json}")
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
      end
    end
  end
end
