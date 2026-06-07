require "./command"

module Enkaidu::Slash
  class ThinkCommand < Command
    NAME = "/think"

    THINK_EFFORT = ["none", "low", "medium", "high", "default"]

    HELP_BRIEF = "`#{NAME} [#{THINK_EFFORT.join(" or ")}]` - Include attachments for next query"
    # HELP_BRIEF = "`#{NAME} [none|low|medium|high|default]` - Request thinking effort, or show current effort"
    HELP = <<-HELP1
    #{HELP_BRIEF}
    - If `none`, disables thinking / reasoning if the model supports it
    - If `low` or `medium` or `high`, enables thinking / reasoning, though granularity depends on the model
    - If `default`, uses the default model reasoning behaviour
    - Else shows the requested thinking effort
    HELP1

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
      if cmd.expect?(NAME)
        show_thinking_effort(session)
      elsif cmd.expect?(NAME, THINK_EFFORT)
        if effort = LLM::Reasoning.parse?(cmd.arg_at?(1).try(&.to_s) || "")
          session.chat.with_reasoning(effort)
        end
        show_thinking_effort(session)
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete command: #{cmd.input}",
          help: HELP, markdown: true)
      end
    end

    private def show_thinking_effort(session)
      session.renderer.respond_with(
        "Thinking effort: #{session.chat.reasoning}")
    end
  end
end
