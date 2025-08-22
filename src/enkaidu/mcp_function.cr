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
      requireds = if tmp = tool_def.dig?("inputSchema", "required")
                    tmp.as_a
                  else
                    [] of String
                  end
      return unless props = tool_def.dig?("inputSchema", "properties")
      props.as_h.each do |p_name, p_def|
        @params << LLM::Param.new(
          name: p_name,
          description: (tmp = p_def["description"]?) ? tmp.as_s : p_name,
          type: LLM::ParamType.from(label: p_def["type"]),
          required: requireds != nil && requireds.includes?(p_name)
        )
      end
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

    # Yield each parameter definition
    def each_param(& : LLM::Param ->)
      params.each { |param| yield param }
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
          requireds = [] of String
          json.object do
            json.field "type", "object"
            json.field "properties" do
              json.object do
                each_param do |param|
                  json.field param.name do
                    json.object do
                      json.field "type", param.type.label
                      json.field "description", param.description
                      requireds << param.name if param.required?
                    end
                  end
                end
              end
            end
            if !requireds.empty?
              json.field "required" do
                json.array do
                  requireds.each do |p_name|
                    json.string p_name
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
