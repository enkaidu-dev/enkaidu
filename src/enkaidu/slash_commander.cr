require "../sucre/command_parser"
require "../tools/image_helper"

module Enkaidu
  # `SlashCommander` provides the `/` command handling support.
  class SlashCommander
    include Tools::ImageHelper

    getter session : Session
    delegate renderer, to: @session

    def initialize(@session); end

    # This class extends Exception. It is a custom error class, so we can raise custom error classes.
    class ArgumentError < Exception; end

    C_BYE     = "/bye"
    C_USE_MCP = "/use_mcp"
    C_TOOL    = "/tool"
    C_TOOLSET = "/toolset"
    C_INCLUDE = "/include"
    C_HELP    = "/help"

    H_C_TOOLSET = <<-HELP1
    `#{C_TOOLSET} [<sub-command>]`
    - `ls`
      - List all built-in toolsets that can be activated
    - `load <TOOLSET_NAME>`
      - Load all the tools from the named toolset
    - `unload <TOOLSET_NAME>`
      - Unload all the tools from the named toolset
    HELP1

    H_C_TOOL = <<-HELP1
    `#{C_TOOL} [<sub-command>]`
    - `ls`
      - List all available tools
    - `info <TOOLNAME>`
      - Provide details about one tool
    HELP1

    H_C_INCLUDE = <<-HELP1
    `#{C_INCLUDE} [<sub-command>]`
    - `image_file <PATH>`
      - Prepare image data from a file to _include_ with the next query;
        make sure the LLM model supports vision/image processing.
    - `text_file <PATH>`
      - Prepare text from a file to _include_ with the next query.
    - `any_file <PATH>`
      - Prepare a file (with it's base name) to _include_ with the next query;
        make sure the LLM model supports file data along.
    HELP1

    H_C_BYE = <<-HELP1
    `#{C_BYE}`
    - Exit Enkaidu
    HELP1

    H_C_USE_MCP = <<-HELP2
    `#{C_USE_MCP} <NAME>`

    `#{C_USE_MCP} <URL> [auth_env=<ENVARNAME>] [transport=auto|legacy|http]`
    - Connect with the specified MCP server and register any available tools
      for use with subsequent queries
    - MCP server can be specified with URL or name from the config file
    - When loading with a URL
      - Optionally specify the transport type; defaults to `auto`
      - Optionally specify name of environment variable that contains the
        authentication token if needed.
    HELP2

    H_C_HELP = <<-HELP3
    `#{C_HELP}`
    - Shows this information
    HELP3

    HELP = <<-HELP
    #{H_C_BYE}

    #{H_C_HELP}

    #{H_C_TOOL}

    #{H_C_TOOLSET}

    #{H_C_USE_MCP}

    #{H_C_INCLUDE}
    HELP

    # Track any query indicators
    getter query_indicators = [] of String

    # Track current inclusions
    @inclusions : LLM::Chat::Inclusions? = nil

    # Current inclusions collector
    private def inclusions
      @inclusions ||= LLM::Chat::Inclusions.new
    end

    # Returns `Inclusions` if present, clearing current inclusion state and indicators; for use
    # with a query.
    def take_inclusions
      hold = @inclusions
      @inclusions = nil
      @query_indicators.clear
      hold
    end

    private def handle_include_command(cmd)
      ok = nil
      if filepath = cmd.arg_at?(2)
        basename = Path.new(filepath).basename
        if cmd.expect? C_INCLUDE, "image_file", String
          inclusions.image_data load_image_file_as_data_url(filepath), basename
          ok = query_indicators << "I:#{basename}"
        elsif cmd.expect? C_INCLUDE, "text_file", String
          inclusions.text File.read(filepath), basename
          ok = query_indicators << "T:#{basename}"
        elsif cmd.expect? C_INCLUDE, "any_file", String
          inclusions.file_data load_file_as_data_url(filepath), basename
          ok = query_indicators << "F:#{basename}"
        end
      end
      renderer.warning_with("ERROR: Unexpected command / parameters: '#{cmd.input}'",
        help: H_C_INCLUDE, markdown: true) if ok.nil?
    rescue e
      renderer.warning_with("ERROR: #{e.message}", help: H_C_INCLUDE, markdown: true)
    end

    private def handle_use_mcp_command(cmd)
      # Check if command meets expectation
      if cmd.expect?(C_USE_MCP, String)
        first_arg = cmd.arg_at?(1)
        raise ArgumentError.new("No MCP server URL or name given.") if first_arg.nil?

        uri = URI.parse(first_arg)
        if uri.scheme.nil?
          handle_use_mcp_with_name(first_arg)
        else
          handle_use_mcp_with_url(cmd)
        end
      elsif cmd.expect?(C_USE_MCP, String, auth_env: String?, transport: ["auto", "legacy", "http", nil])
        handle_use_mcp_with_url(cmd)
      else
        raise ArgumentError.new("ERROR: Unexpected command / parameters")
      end
    rescue e : ArgumentError
      renderer.warning_with(e.message, help: H_C_USE_MCP, markdown: true)
    end

    private def handle_use_mcp_with_name(name)
      session.use_mcp_by(name)
    end

    private def handle_use_mcp_with_url(cmd)
      auth_key = nil
      type = MCPC::TransportType::AutoDetect

      raise ArgumentError.new("ERROR: Specify URL to the MCP server") if (url = cmd.arg_at?(1)).nil?
      if (auth_env = cmd.arg_named?("auth_env")) && (auth_key = ENV[auth_env]?).nil?
        raise ArgumentError.new("ERROR: Unable to find environment variable: #{auth_env}.")
      end

      if transport_arg = cmd.arg_named?("transport")
        type = MCPC::TransportType.from(transport_arg)
      end
      auth_token = auth_token_for_bearer_token(url, auth_key)
      session.use_mcp_server url.as(String), auth_token: auth_token, transport_type: type
    end

    private def auth_token_for_bearer_token(url, bearer_token)
      return if bearer_token.nil?

      MCPC::AuthToken.new(label: "MCP auth token: #{url}", value: bearer_token)
    end

    private def handle_tool_command(cmd)
      if cmd.expect?(C_TOOL, "ls")
        session.list_all_tools
      elsif cmd.expect?(C_TOOL, "info", String)
        session.list_tool_details((cmd.arg_at? 2).as(String))
      else
        renderer.warning_with("ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}", help: H_C_TOOL, markdown: true)
      end
    end

    private def handle_toolset_command(cmd)
      if cmd.expect?(C_TOOLSET, "ls")
        session.list_all_toolsets
      elsif cmd.expect?(C_TOOLSET, "load", String)
        if name = cmd.arg_at?(2)
          session.load_toolset_by(name)
        end
      elsif cmd.expect?(C_TOOLSET, "unload", String)
        if name = cmd.arg_at?(2)
          session.unload_toolset_by(name)
        end
      else
        renderer.warning_with("ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}", help: H_C_TOOLSET, markdown: true)
      end
    end

    # Returns :done if user says `/bye`
    def make_it_so(q)
      state = nil
      cmd = CommandParser.new(q)
      case cmd.arg_at?(0)
      when C_BYE
        state = :done
      when C_HELP
        renderer.info_with "The following `/` (slash) commands available:",
          help: HELP, markdown: true
      when C_TOOL
        handle_tool_command(cmd)
      when C_TOOLSET
        handle_toolset_command(cmd)
      when C_USE_MCP
        handle_use_mcp_command(cmd)
      when C_INCLUDE
        handle_include_command(cmd)
      else
        renderer.warning_with("ERROR: Unknown command: #{q}")
      end
      state
    end
  end
end
