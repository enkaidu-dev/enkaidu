require "colorize"

require "../llm"
require "../mcpc"

module Enkaidu
  # Defines a tool / function from an MCP server
  class MCPFunction < LLM::Function
    getter name : String
    getter title : String? = nil
    getter description : String

    # Accessible to the function's Runner
    protected getter params : Array(LLM::Param)
    protected getter mcpc : MCPC::HttpConnection
    protected getter cli : Session

    @input_schema : JSON::Any

    # Initialize with the JSON representation of the tool return by MCP "tools/list", and the
    # MCPC connection to use to make the tool call
    def initialize(tool_def : JSON::Any, @mcpc, @cli)
      @params = [] of LLM::Param
      # Extract the function specification from the tool definition
      @origin = mcpc.origin
      @name = tool_def["name"].as_s
      if tmp = tool_def["title"]?
        @title = tmp.as_s
      end
      @description = if tmp = tool_def["description"]?
                       tmp.as_s
                     else
                       @name # if no description, use name as description.
                     end
      @input_schema = tool_def["inputSchema"]
    end

    # The input schema for the parameters to this function, into the JSON builder.
    def input_json_schema(json : JSON::Builder)
      @input_schema.to_json(json)
    end

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < LLM::Function::Runner
      private getter func : MCPFunction

      def initialize(@func); end

      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        func.cli.renderer.mcp_calling_tool(func.mcpc.uri, func.name, args)
        if result = func.mcpc.call_tool(func.name, args.as_h)
          result = result.to_json
          func.cli.renderer.mcp_calling_tool_result(func.mcpc.uri, func.name, result)
          result
        else
          "null"
        end
      rescue ex
        func.cli.handle_mcpc_error(ex)
        "null"
      end
    end

    # Return an instance of this function's Runner
    def new_runner : Runner
      Runner.new(self)
    end

    def to_s(io)
      JSON.build(io) { |json| build_json(json) }
    end

    def to_json
      JSON.build { |json| build_json(json) }
    end

    private def build_json(json : JSON::Builder)
      json.object do
        json.field "name", name
        json.field "description", description
        json.field "title", title
        json.field "inputSchema" do
          input_json_schema(json)
        end
      end
    end
  end
end
