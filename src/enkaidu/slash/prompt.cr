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
    - `use <PROMPTNAME>`
      - Use (invoke) a prompt by name. If the prompt requirements arguments, you will be prompted for input per argument.
    HELP1

    private getter commander : Commander

    def initialize(@commander); end

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.current.session
      if cmd.expect?(NAME, "ls")
        session.list_all_prompts
      elsif cmd.expect?(NAME, "info", String)
        session.list_prompt_details((cmd.arg_at? 2).as(String))
      elsif cmd.expect?(NAME, "use", String, show: ["yes", "no", nil])
        show = cmd.arg_named?("show", "yes").try(&.==("yes"))
        schema = commander.take_response_schema!
        inclusions = commander.take_inclusions!
        session.use_prompt(prompt_name: (cmd.arg_at? 2).as(String),
          show: show, attach: inclusions, response_schema: schema)
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end
  end
end
