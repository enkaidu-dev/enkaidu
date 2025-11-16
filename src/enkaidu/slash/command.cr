require "../../sucre/command_parser"
require "../session_manager"

module Enkaidu::Slash
  abstract class Command
    abstract def help : String

    abstract def name : String

    abstract def handle(session_manager : SessionManager, cmd : CommandParser)
  end
end
