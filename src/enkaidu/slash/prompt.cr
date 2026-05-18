require "./command"

module Enkaidu::Slash
  class PromptCommand < Command
    NAME = "/prompt"

    HELP_BRIEF = "`#{NAME} [<sub-command>]` - Manage custom prompts"

    HELP = <<-HELP1
    #{HELP_BRIEF}
    - `ls`
      - List all available prompt
    - `info <PROMPTNAME>`
      - Provide details about one prompt
    - `use <PROMPTNAME> [NAME=VALUE ...]`
      - Use (invoke) a prompt by name.
      - If the prompt requirements arguments, you will be prompted for input per argument.
      - If you provide values for any arguments by name, those values will be used without prompting
    HELP1

    private getter commander : Commander

    def initialize(@commander); end

    def name : String
      NAME
    end

    def brief : String
      HELP_BRIEF
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
      elsif cmd.arg_at?(0).try(&.==(NAME)) && cmd.arg_at?(1).try(&.==("use"))
        if (prompt = cmd.arg_at?(2)) && prompt.is_a?(String)
          invoke_prompt(session, cmd, prompt)
        else
          session.renderer.warning_with(
            "ERROR: Prompt name required to use a prompt",
            help: HELP, markdown: true)
        end
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end

    private def invoke_prompt(session, cmd, prompt)
      # /macro use ...
      # Gather up arguments, positional and named into a hash
      # Positional ones with 0-index (from starting position) as key
      # Named ones by names
      params = {} of String => String | Array(String)
      (2...cmd.positional_count).each do |i|
        params[(i - 2).to_s] = cmd.arg_at(i)
      end
      cmd.each_named do |key, value|
        params[key] = value
      end
      # Gather up attachment, response schema and call session
      schema = commander.take_response_schema!
      inclusions = commander.take_inclusions!
      session.use_prompt(prompt_name: prompt, params: params,
        attach: inclusions, response_schema: schema)
    end
  end
end
