require "../../sucre/command_parser"

module Enkaidu::Slash
  abstract class Command
    abstract def help : String

    abstract def name : String

    abstract def handle(session, cmd : CommandParser)
  end
end
