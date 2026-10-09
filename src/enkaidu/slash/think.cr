require "./command"

module Enkaidu::Slash
  class ThinkCommand < Command
    NAME = "/think"

    THINK_EFFORT = LLM::Reasoning.names.map(&.downcase)
    THINK_LEVELS = (LLM::Reasoning.values.reject { |eff| eff.default? || eff.none? }).map(&.to_s.downcase)

    HELP_BRIEF = "`#{NAME} [<sub-command>]` - Thinking, aka reasoning effort, control"

    HELP = <<-HELP1
      #{HELP_BRIEF}
      - `current`
        - Shows the currently configured (or default) thinking / reasoning effort
      - `set #{THINK_EFFORT.join(" or ")}`
        - `none` disables thinking / reasoning if the model supports it
        - `default` resets to use the model's default thinking level
        - #{(THINK_LEVELS.map { |eff| "`#{eff}`" }).join(", ")} enable thinking / reasoning as supported by model
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
      if cmd.expect?(NAME, "current")
        show_thinking_effort(session)
      elsif cmd.expect?(NAME, "set", THINK_EFFORT)
        if effort = LLM::Reasoning.parse?(cmd.arg_at?(2).try(&.to_s) || "")
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
