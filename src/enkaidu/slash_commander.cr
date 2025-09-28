require "../sucre/command_parser"
require "../tools/image_helper"
require "./slash/*"

module Enkaidu::Slash
  # `Slash::Commander` provides the `/` command handling support.
  class Commander
    include Tools::ImageHelper

    private getter commands = {} of String => Command

    getter session : Session
    delegate renderer, to: @session

    def initialize(@session)
      register_commands
    end

    private def register_commands
      [
        SessionCommand.new,
        ToolCommand.new,
        ToolsetCommand.new,
        UseMcpCommand.new,
      ].each do |command|
        commands[command.name] = command
      end
    end

    # This class extends Exception. It is a custom error class, so we can raise custom error classes.
    class ArgumentError < Exception; end

    C_BYE     = "/bye"
    C_INCLUDE = "/include"
    C_HELP    = "/help"

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

    H_C_HELP = <<-HELP3
    `#{C_HELP}`
    - Shows this information
    HELP3

    def help
      @help ||= <<-HELP
      #{H_C_BYE}

      #{H_C_HELP}

      #{commands[SessionCommand::NAME].try &.help}

      #{commands[ToolCommand::NAME].try &.help}

      #{commands[ToolsetCommand::NAME].try &.help}

      #{commands[UseMcpCommand::NAME].try &.help}

      #{H_C_INCLUDE}
      HELP
    end

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
      if filepath = cmd.arg_at?(2).try(&.as(String))
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
      renderer.warning_with("ERROR: Unknown or incomplete sub-command: '#{cmd.input}'",
        help: H_C_INCLUDE, markdown: true) if ok.nil?
    rescue e
      renderer.warning_with("ERROR: #{e.message}", help: H_C_INCLUDE, markdown: true)
    end

    # Returns :done if user says `/bye`
    def make_it_so(q)
      state = nil
      cmd = CommandParser.new(q)

      case cmd_name = cmd.arg_at?(0)
      when C_BYE
        state = :done
      when C_HELP
        renderer.info_with "The following `/` (slash) commands available:",
          help: help, markdown: true
      when C_INCLUDE
        handle_include_command(cmd)
      else
        if command = commands[cmd_name]?
          command.handle(session, cmd)
        else
          renderer.warning_with("ERROR: Unknown command: #{q}")
        end
      end
      state
    end
  end
end
