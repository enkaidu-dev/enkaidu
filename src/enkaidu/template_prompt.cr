require "colorize"
require "liquid"

require "./config"

module Enkaidu
  # Defines a templated prompt from configuration
  class TemplatePrompt
    @[JSON::Field(ignore: true)]
    protected getter cli : Session

    def origin
      "Enkaidu/Config"
    end

    class Argument < Config::Prompt::Arg
      getter name : String

      def initialize(@name, arg)
        @description = arg.description
      end
    end

    getter arguments = [] of Argument
    getter description : String
    getter name : String

    def initialize(@name, prompt : Config::Prompt, @cli)
      @description = prompt.description
      @template = Liquid::Template.parse(prompt.template)
      prompt.arguments.try(&.each { |arg_name, arg| arguments << Argument.new(arg_name, arg) })
    end

    def call_with(args : Hash(String, String)) : String
      ctx = Liquid::Context.new
      args.each do |key, value|
        ctx.set(key, value)
      end
      @template.render(ctx)
    end
  end
end
