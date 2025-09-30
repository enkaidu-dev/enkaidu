require "./command"

module Enkaidu::Slash
  class PromptCommand < Command
    NAME = "/prompt"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `ls`
      - List all available prompt
    - `info <PROMPTNAME>`
      - Provide details about one prompt
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    def handle(session, cmd : CommandParser)
      if cmd.expect?(NAME, "ls")
        session.list_all_prompts
      elsif cmd.expect?(NAME, "info", String)
        session.list_prompt_details((cmd.arg_at? 2).as(String))
      elsif cmd.expect?(NAME, "use", String)
        session.use_prompt((cmd.arg_at? 2).as(String))
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end
  end
end
