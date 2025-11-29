require "colorize"
require "liquid"

require "./config"
require "./env"

module Enkaidu
  # Defines a templated prompt that can be invoked with arguments as well as
  # system and profile properties.
  #
  # - Arguments are available with the `arg.` prefix
  # - Profile variables are available with the `var.` prefix
  # - System properties are available via the `sys.` prefix
  class TemplatePrompt
    protected getter cli : Session
    getter origin : String

    class Argument < Config::Prompt::Arg
      getter name : String

      def initialize(@name, arg)
        @description = arg.description
      end
    end

    getter arguments = [] of Argument
    getter description : String
    getter name : String

    def initialize(@name, prompt : Config::Prompt, @cli, @origin = "Enkaidu/Config")
      @description = prompt.description
      @template = Liquid::Template.parse(prompt.template)
      prompt.arguments.try(&.each { |arg_name, arg| arguments << Argument.new(arg_name, arg) })
    end

    def initialize(@name, sys_prompt : Config::SystemPrompt, @cli, @origin = "Enkaidu/Config")
      @description = sys_prompt.description || "(A system prompt)"
      @template = Liquid::Template.parse(sys_prompt.template)
    end

    def render(args : Hash(String, String)? = nil, profile : Env::Profile? = nil) : String
      ctx = Liquid::Context.new
      if args
        ctx.set("arg", liquify(args))
      end

      #
      # YUCK - don't generate these every time; right now I can't yet think of
      #        way that doesn't leak the use of the `Liquid::Any` type
      ctx.set("var", liquify(profile.variables))
      ctx.set("sys", liquify(Env::SYSTEM_PROPERTIES))

      @template.render(ctx)
    end

    private def liquify(vars)
      vars.transform_values do |value|
        case value
        when Array
          Liquid::Any.new(value.map { |item| Liquid::Any.new(item) })
        when Hash
          Liquid::Any.new(value.transform_values do |val|
            case val
            when Array
              Liquid::Any.new(val.map { |item| Liquid::Any.new(item) })
            else
              Liquid::Any.new(val)
            end
          end)
        else
          Liquid::Any.new(value)
        end
      end
    end
  end
end
