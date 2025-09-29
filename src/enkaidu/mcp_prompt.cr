require "colorize"

require "../llm"
require "../mcpc"

module Enkaidu
  # Defines a prompt from an MCP server
  class MCPPrompt < MCPC::Prompt
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
      prompt_args = [] of MCPC::Prompt::Argument
      arg_defs.each do |arg_def|
        prompt_args << MCPC::Prompt::Argument.new(
          name: arg_def["name"].as_s,
          title: arg_def["title"]?.try(&.as_s),
          description: arg_def["description"]?.try(&.as_s),
          required: arg_def["required"]?.try(&.as_bool?) || false
        )
      end
      prompt_args
    end
  end
end
