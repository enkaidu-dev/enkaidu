require "./command"

module Enkaidu::Slash
  class MacroCommand < Command
    NAME = "/macro"

    HELP_BRIEF = "`#{NAME} [<sub-command>]` - Manage macros"

    HELP = <<-HELP1
      #{HELP_BRIEF}
      - `ls`
        - List all available macros.
        - Macros can be executed by using the `!` sigil before the name of the macro. E.g. `!test`
      HELP1

    def name : String
      NAME
    end

    def brief : String
      HELP_BRIEF
    end

    def help : String
      HELP
    end

    getter macro_helper : MacroProcessingHelper

    def initialize(@macro_helper)
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.current.session
      if cmd.expect?(NAME, "ls")
        list_all_macros(session.renderer)
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end

    # ----------

    private def list_all_macros(renderer)
      text = String.build do |io|
        macro_helper.each_macro do |name, mac, origin|
          io.puts "----"
          io << "`" << name << "` (_" << origin << "_) - "
          io << mac.description << "\n\n"
        end
        io << '\n'
      end
      renderer.respond_with("List of available macros.", text, markdown: true)
    end
  end
end
