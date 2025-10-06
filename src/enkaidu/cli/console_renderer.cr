require "reply"
require "../session_renderer"

require "markterm"

module Enkaidu::CLI
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

  # This class is responsible for rendering console outputs.
  class ConsoleRenderer < SessionRenderer
    property? streaming = false
    private getter input = InputReader.new("> ")

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

    def user_query_text(query)
      print "QUERY > ".colorize(:yellow)
      puts query
    end

    def user_query_image_url(url)
      print "QUERY > ".colorize(:yellow)
      puts "IMAGE #{trim_text(url, MAX_IMAGE_URL_LENGTH)}".colorize(:green)
    end

    def user_confirm_shell_command?(command)
      puts "  CONFIRM: The assistant wants to run the following command:\n"
      puts "  > #{command}\n\n".colorize(:red).bold
      print "  Allow? [y/N] "
      response = STDIN.raw &.read_char
      puts response

      ['y', 'Y'].includes?(response)
    end

    private RESET = <<-ANSI
     ______     ______     ______     ______     ______
    /\\  == \\   /\\  ___\\   /\\  ___\\   /\\  ___\\   /\\__  _\\
    \\ \\  __<   \\ \\  __\\   \\ \\___  \\  \\ \\  __\\   \\/_/\\ \\/
     \\ \\_\\ \\_\\  \\ \\_____\\  \\/\\_____\\  \\ \\_____\\    \\ \\_\\
      \\/_/ /_/   \\/_____/   \\/_____/   \\/_____/     \\/_/


    ANSI

    def session_reset
      3.times { puts }
      puts RESET
    end

    LLM_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def llm_tool_call(name, args)
      print "  CALL".colorize(:green)
      puts " #{name.colorize(:red)} " \
           "with #{trim_text(args.to_s, LLM_MAX_TOOL_CALL_ARGS_LENGTH).colorize(:red)}"
      puts
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

    def llm_text_block(text)
      puts Markd.to_term(text)
      puts
    end

    MAX_IMAGE_URL_LENGTH = 72

    def llm_image_url(url)
      puts "  IMAGE #{trim_text(url, MAX_IMAGE_URL_LENGTH)}".colorize(:green)
      puts
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

    def mcp_prompts_found(count)
      puts "  FOUND #{count} prompts".colorize(:green)
    end

    def mcp_prompt_ready(prompt)
      puts "  FOUND prompt: #{prompt.name}".colorize(:green)
    end

    private def ask_param_input(name, description, color)
      text = if description
               "    #{name} [#{description}] :"
             else
               "    #{name} : "
             end
      puts text.colorize(color)
      input.label = "    > "
      input.read_next
    end

    def mcp_prompt_ask_input(prompt : MCPPrompt) : Hash(String, String)
      text = <<-PREFIX
          #{prompt.description}

      PREFIX
      puts text.colorize(:cyan)

      arg_inputs = {} of String => String
      prompt.arguments.try &.each do |arg|
        unless (value = ask_param_input(arg.name, arg.description, :cyan)).nil?
          arg_inputs[arg.name] = value
        end
      end
      puts
      arg_inputs
    end

    def user_prompt_ask_input(prompt : TemplatePrompt) : Hash(String, String)
      text = <<-PREFIX
          #{prompt.description}

      PREFIX
      puts text.colorize(:green)

      arg_inputs = {} of String => String
      prompt.arguments.try &.each do |arg|
        unless (value = ask_param_input(arg.name, arg.description, :green)).nil?
          arg_inputs[arg.name] = value
        end
      end
      puts
      arg_inputs
    end

    MCP_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def mcp_calling_tool(uri, name, args)
      puts "  MCP CALLING \"#{name}\" at server #{uri}.".colorize(:yellow)
      puts "      with: #{trim_text(args.to_s, MCP_MAX_TOOL_CALL_ARGS_LENGTH)}".colorize(:yellow)
    end

    MCP_MAX_TOOL_RESULT_LENGTH = 72

    def mcp_calling_tool_result(uri, name, result)
      puts "  MCP CALL (#{name}) RESULT: #{trim_text(result.to_s, MCP_MAX_TOOL_RESULT_LENGTH)}".colorize(:green)
      puts
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
