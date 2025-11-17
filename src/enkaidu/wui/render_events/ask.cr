require "json"

require "./event"
require "../../../sucre/mcp_types"

module Enkaidu::WUI::Render
  enum InputType
    Text
  end

  class InputArgument
    include JSON::Serializable

    getter name : String
    getter description : String?
    getter type : InputType

    def initialize(@name, @description, @type = InputType::Text); end
  end

  class InvalidInputAsk < Exception; end

  class AskForInputs < Event
    getter id : String
    getter description : String
    getter arguments : Array(InputArgument)
    getter title : String

    def initialize(@id, prompt : MCP::Prompt)
      prompt_args = prompt.arguments
      raise InvalidInputAsk.new("Asking for input requires arguments") if prompt_args.nil?

      super("ask_for_inputs")
      @title = "Input required for MCP Prompt: #{prompt.name}"
      @description = prompt.description || prompt.name.titleize
      @arguments = prompt_args.map do |prompt_arg|
        InputArgument.new(prompt_arg.name,
          description: prompt_arg.description || prompt_arg.title,
          type: InputType::Text)
      end
    end

    def initialize(@id, prompt : TemplatePrompt)
      prompt_args = prompt.arguments

      super("ask_for_inputs")
      @title = "Input required for User Prompt: #{prompt.name}"
      @description = prompt.description
      @arguments = prompt_args.map do |prompt_arg|
        InputArgument.new(prompt_arg.name,
          description: prompt_arg.description,
          type: InputType::Text)
      end
    end
  end
end
