require "colorize"

require "../sucre/mcp_types"
require "../llm"
require "../mcpc"

module Enkaidu
  # Defines a prompt from an MCP server
  class MCPPrompt < MCP::Prompt
    # Accessible to the function's Runner

    @[JSON::Field(ignore: true)]
    protected getter mcpc : MCPC::HttpConnection
    @[JSON::Field(ignore: true)]
    protected getter cli : Session

    delegate origin, to: @mcpc

    # Initialize with the JSON representation of the tool return by MCP "prompts/list", and the
    # MCPC connection to use to make the tool call
    def initialize(prompt_def : JSON::Any, @mcpc, @cli)
      @arguments = nil
      @name = prompt_def["name"].as_s
      if tmp = prompt_def["title"]?
        @title = tmp.as_s
      end
      @description = prompt_def["description"]?.try(&.as_s) || title || name
      if args = prompt_def["arguments"]?
        @arguments = extract_arguments(args.as_a)
      end
    end

    private def extract_arguments(arg_defs : Array(JSON::Any))
      prompt_args = [] of MCP::Prompt::Argument
      arg_defs.each do |arg_def|
        prompt_args << MCP::Prompt::Argument.new(
          name: arg_def["name"].as_s,
          title: arg_def["title"]?.try(&.as_s),
          description: arg_def["description"]?.try(&.as_s),
          required: arg_def["required"]?.try(&.as_bool?) || false
        )
      end
      prompt_args
    end

    def render(args : Hash(String, String))
      mcpc.get_prompt(name, args)
    end
  end
end
