require "json"

require "./prompt_result"

module MCP
  # The definition for an MCP Prompt
  class Prompt
    include JSON::Serializable

    # The definition for an MCP Prompt argument
    class Argument
      include JSON::Serializable

      getter name : String
      getter description : String?
      getter title : String?
      getter? required : Bool

      def initialize(@name, @description = nil, @title = nil, @required = false); end
    end

    getter name : String
    getter description : String?
    getter title : String?
    getter arguments : Array(Argument)?
  end
end
