require "termify"
require "colorize"
require "markterm"

require "./style_sheet"
require "./input_reader"

require "../session_renderer"

module Enkaidu::Console
  # This class is responsible for rendering console outputs.
  class Renderer < SessionRenderer
    include StyleApplicator

    property? streaming = false
    property? quiet = false

    # Markdown rendering stylesheet for use with Termify
    MDR_STYLESHEET = Termify::Markdown::Stylesheet.new({
      :h1          => {bold: true, line_prefix: "# ".colorize(:dark_gray).to_s},
      :h2          => {bold: true, line_prefix: "## ".colorize(:dark_gray).to_s},
      :h3          => {bold: true, line_prefix: "### ".colorize(:dark_gray).to_s},
      :h4          => {bold: true},
      :h5          => {bold: true},
      :h6          => {bold: true},
      :code_block  => {fg: "cyan", line_prefix: "░ "},
      :code_inline => {fg: "cyan"},
      :html_tag    => {dim: true},
      :block_html  => {dim: true},
      :table       => {fg: "white"},
      :block_quote => {line_prefix: "▌ "},
    })

    private getter input = InputReader.new("> ")

    private def prepare_text(help, markdown)
      markdown ? Markd.to_term(help.to_s) : help
    end

    private def err_puts_text(help, markdown)
      text = prepare_text(help, markdown)
      STDERR.puts unless text.to_s.starts_with? '\n'
      STDERR.puts text
    end

    def respond_with(message, help = nil, markdown = false)
      puts fmt(:response, message)
      return unless help
      puts prepare_text(help, markdown)
    end

    def info_with(message, help = nil, markdown = false)
      return if quiet?
      STDERR.puts fmt(:info, message)
      return unless help
      err_puts_text help, markdown
    end

    def warning_with(message, help = nil, markdown = false)
      STDERR.puts fmt(:warning, message)
      return unless help
      err_puts_text help, markdown
    end

    def error_with(message, help = nil, markdown = false)
      STDERR.puts fmt(:error, message)
      return unless help
      err_puts_text help, markdown
    end

    def time_elapsed(duration : Time::Span, label : String? = nil)
      puts if streaming?
      elapsed = duration.total_seconds.format(decimal_places: 3, only_significant: true)
      puts fmt(:after_reply, "#{label}#{elapsed}s elapsed.")
    end

    def user_query_text(query, via_query_queue = false)
      cat = via_query_queue ? :query_prefix_by_queue : :query_prefix_by_user
      prefix0 = fmt(cat, "QUERY > ")
      prefix1 = fmt(cat, "      > ")
      query_lines = query.split('\n')
      query_lines.each_with_index do |line, index|
        print index.zero? ? prefix0 : prefix1
        puts line
      end
    end

    def user_query_image_url(url)
      print fmt(:query_prefix_by_user, "QUERY > ")
      puts fmt(:query_feedback, "IMAGE #{trim_text(url, MAX_IMAGE_URL_LENGTH)}")
    end

    def user_confirm_shell_command?(command)
      puts fmt(:confirm_question, "  CONFIRM: The assistant wants to run the following command:\n")
      puts fmt(:confirm_content, "  > #{command}\n\n")
      print fmt(:confirm_question, "  Allow? [y/N] ")
      response = STDIN.raw &.read_char
      puts fmt(:confirm_input, response.to_s)

      ['y', 'Y'].includes?(response)
    end

    private RESET = <<-ANSI
    ░░░░░░  ░░░░░░░ ░░░░░░░ ░░░░░░░ ░░░░░░░░
    ▒▒   ▒▒ ▒▒      ▒▒      ▒▒         ▒▒
    ▒▒▒▒▒▒  ▒▒▒▒▒   ▒▒▒▒▒▒▒ ▒▒▒▒▒      ▒▒
    ▓▓   ▓▓ ▓▓           ▓▓ ▓▓         ▓▓
    ██   ██ ███████ ███████ ███████    ██
    ANSI

    private SWITCHED = <<-ANSI
    ░░░░░░░ ░░     ░░ ░░ ░░░░░░░░  ░░░░░░ ░░   ░░ ░░░░░░░ ░░░░░░
    ▒▒      ▒▒     ▒▒ ▒▒    ▒▒    ▒▒      ▒▒   ▒▒ ▒▒      ▒▒   ▒▒
    ▒▒▒▒▒▒▒ ▒▒  ▒  ▒▒ ▒▒    ▒▒    ▒▒      ▒▒▒▒▒▒▒ ▒▒▒▒▒   ▒▒   ▒▒
         ▓▓ ▓▓ ▓▓▓ ▓▓ ▓▓    ▓▓    ▓▓      ▓▓   ▓▓ ▓▓      ▓▓   ▓▓
    ███████  ███ ███  ██    ██     ██████ ██   ██ ███████ ██████
    ANSI

    def session_reset
      puts fmt(:session_banner, RESET)
    end

    def session_pushed(depth, keep_tools, keep_prompts, keep_history)
      puts fmt(:session_open, "┌─── SESSION PUSHED (#{depth}) ─────────────────────#{keep_history ? "─────" : "─ No history ─────"}")
    end

    def session_popped(depth)
      puts fmt(:session_close, "└───────────────────────────────────────────────────────────")
    end

    def session_stack_new(name)
      # IMPROVE this later
      session_stack_changed(name)
    end

    def session_stack_changed(name)
      puts
      puts fmt(:session_banner, SWITCHED)
    end

    LLM_MAX_TOOL_CALL_ARGS_LENGTH = 90

    def llm_tool_call(name, args)
      puts if streaming? unless quiet?

      args_json = JSON.parse(args.as_s)
      trim_more = name.size + 5
      print "  " if quiet?

      prop_reason = args_json.dig?("reason").try(&.as_s?)
      if reason = prop_reason
        print fmt(:tool_call_reason, "→ #{reason} ")
        trim_more += reason.size + 2
      else
        print fmt(:tool_call_reason, "→ ")
        trim_more += 2
      end

      if quiet?
        puts fmt(:tool_call_detail, " ~ CALL #{name}")
      else
        trim_length = (LLM_MAX_TOOL_CALL_ARGS_LENGTH - trim_more).clamp(32, LLM_MAX_TOOL_CALL_ARGS_LENGTH)
        print fmt(:tool_call_detail, "\n  └─") if prop_reason
        puts fmt(:tool_call_detail, "CALL #{name} #{trim_text(args.to_s, trim_length)}")
      end

      puts unless streaming? || quiet?
    end

    def llm_error(err)
      warning_with("ERROR:\n#{err.to_json}")
    end

    class Counter
      SPINNER_CHARS = ['|', '/', '-', '\\']
      getter count = 0

      def reset
        @count = 0
      end

      def spin
        tmp = SPINNER_CHARS[(count // 3) % SPINNER_CHARS.size]
        @count += 1
        tmp
      end
    end

    @think_counter = Counter.new

    @md_renderer = Termify::Markdown::Renderer.new(STDOUT, MDR_STYLESHEET)

    private def render_streaming_markdown(text, _starting : Bool, ending : Bool)
      @md_renderer << text
      @md_renderer.puts if ending
    end

    def llm_text(text, reasoning : Bool, starting : Bool = false, ending : Bool = false)
      if streaming?
        if reasoning
          if quiet?
            if starting
              print fmt(:thinking_progress, "  Thinking  ")
              @think_counter.reset
            end
            if ending
              print "\r                          \r"
            else
              print "\b", @think_counter.spin
            end
          else
            puts "", fmt(:thinking_content, REASONING_START) if starting
            print fmt(:thinking_content, text)
            puts "", fmt(:thinking_content, REASONING_FINISH) if ending
          end
        else
          render_streaming_markdown(text, starting, ending)
        end
      else
        llm_text_block(text, reasoning)
      end
    end

    REASONING_START  = "╭╶╶╶╶╶╶╶╶╶╶< reasoning >╶╶╶╶╶╶╶╶╶╶╶"
    REASONING_FINISH = "╰╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶"

    def llm_text_block(text, reasoning : Bool)
      puts unless reasoning
      puts fmt(:thinking_content, REASONING_START) if reasoning
      puts Markd.to_term(text)
      puts fmt(:thinking_content, REASONING_FINISH) if reasoning
      puts unless reasoning
    end

    MAX_IMAGE_URL_LENGTH = 72

    def llm_image_url(url)
      puts fmt(:query_feedback, "  IMAGE #{trim_text(url, MAX_IMAGE_URL_LENGTH)}")
      puts
    end

    def mcp_initialized(uri)
      puts fmt(:mcp_feedback, "  INIT MCP connection: #{uri}")
    end

    def mcp_tools_found(count)
      puts fmt(:mcp_feedback, "  FOUND #{count} tools")
    end

    def mcp_tool_ready(function)
      puts fmt(:mcp_feedback, "  └─ function: #{function.name}")
    end

    def mcp_prompts_found(count)
      puts fmt(:mcp_feedback, "  FOUND #{count} prompts")
    end

    def mcp_prompt_ready(prompt)
      puts fmt(:mcp_feedback, "  └─ prompt: #{prompt.name}")
    end

    private def ask_param_input(name, description)
      text = if description
               "    #{name} [#{description}] :"
             else
               "    #{name} : "
             end
      puts fmt(:prompt_question, text)
      input.label = fmt(:prompt_input, "    > ")
      input.read_next
    end

    private def ask_prompt_inputs(prompt) : Hash(String, String)
      text = <<-PREFIX
          #{prompt.description}

      PREFIX
      puts fmt(:prompt_content, text)

      arg_inputs = {} of String => String
      prompt.arguments.try &.each do |arg|
        unless (value = ask_param_input(arg.name, arg.description)).nil?
          arg_inputs[arg.name] = value
        end
      end
      puts
      arg_inputs
    end

    def mcp_prompt_ask_input(prompt : MCPPrompt) : Hash(String, String)
      ask_prompt_inputs(prompt)
    end

    def user_prompt_ask_input(prompt : TemplatePrompt) : Hash(String, String)
      ask_prompt_inputs(prompt)
    end

    MCP_MAX_TOOL_CALL_ARGS_LENGTH = 72

    def mcp_calling_tool(uri, name, args)
      unless quiet?
        puts if streaming?
        puts fmt(:mcp_action, "→ MCP CALLING \"#{name}\" at server #{uri}.")
        puts fmt(:mcp_action, "  └─ with: #{trim_text(args.to_s, MCP_MAX_TOOL_CALL_ARGS_LENGTH)}")
      end
    end

    MCP_MAX_TOOL_RESULT_LENGTH = 72

    def mcp_calling_tool_result(uri, name, result)
      unless quiet?
        puts fmt(:mcp_action, "  MCP CALL (#{name}) RESULT: #{trim_text(result.to_s, MCP_MAX_TOOL_RESULT_LENGTH)}")
        puts
      end
    end

    def mcp_error(ex)
      error_with "ERROR: #{ex.class}: #{ex}", markdown: true,
        help: (String.build do |io|
          io.print "```"
          case ex
          when MCPC::ResponseError
            io.puts "json"
            io.puts(JSON.build(indent: 2) { |builder| ex.details.to_json(builder) })
          when MCPC::ResultError
            io.puts "json"
            io.puts(JSON.build(indent: 2) { |builder| ex.data.to_json(builder) })
          else
            io.puts
            io.puts ex.inspect_with_backtrace
          end
          io.puts "```"
        end)
    end

    private def trim_text(text, max_length)
      suffix = ""
      str = text
      if str.size > max_length
        str = str[..max_length]
        suffix = "... >8"
      end
      "#{str}#{suffix}"
    end
  end
end
