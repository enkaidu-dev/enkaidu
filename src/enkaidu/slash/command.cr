require "../../sucre/command_parser"
require "../session_manager"

module Enkaidu::Slash
  abstract class Command
    # Detailed help, in Markdown
    abstract def help : String

    # One line help, in Markdown
    abstract def brief : String

    abstract def name : String

    abstract def handle(session_manager : SessionManager, cmd : CommandParser)
  end
end
