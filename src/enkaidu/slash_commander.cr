require "../sucre/command_parser"
require "../tools/image_helper"
require "./slash/*"

module Enkaidu::Slash
  # `Slash::Commander` provides the `/` command handling support.
  class Commander
    private getter commands = {} of String => Command

    private getter include_command = IncludeCommand.new

    getter session : Session
    delegate renderer, to: @session

    def initialize(@session)
      register_commands
    end

    private def register_commands
      [
        include_command, # tracked locally to access inclusions
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

    C_BYE  = "/bye"
    C_HELP = "/help"

    H_C_BYE = <<-HELP1
    `#{C_BYE}`
    - Exit Enkaidu
    HELP1

    H_C_HELP = <<-HELP3
    `#{C_HELP}`
    - Shows this information
    HELP3

    def help
      @help ||= String.build do |sio|
        sio.puts H_C_BYE
        sio.puts
        sio.puts H_C_HELP
        sio.puts
        commands.each_value do |command|
          sio.puts command.help
          sio.puts
        end
      end
    end

    delegate query_indicators, take_inclusions!, to: @include_command

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
