require "./command"

module Enkaidu::Slash
  class SessionCommand < Command
    NAME = "/session"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `usage`
      - Show the token usage / size for the current session based on
        most recent response from LLM
    - `save <FILEPATH>`
      - Save the current chat session to a JSONL file
      - Records current toolsets and tools
      - Records MCP connections _iff_ they match MCP servers defined in the config file
      - NOTE: The file should not be edited.
    - `load <FILEPATH> [tail=<N>]`
      - Load a saved chat session from its JSONL file.
      - Clears all active tools and MCP connections
      - Restores toolsets and re-establishes MCP server connections
      - Optionally specify how many `N` recent chats to display after loading the session.
    - `reset`
      - Clears all active tools and MCP connections
      - Throws away the current session / context
      - Auto loads tools and MCP connections in the configuration
    - `push [keep_tools=yes|no] [keep_prompts=yes|no] [keep_history=yes|no]`
      - Pushes current session onto session stack
      - Forks a new session, keeping tools, prompts, and history as specified
      - By default the new session keeps all state
    - `pop`
      - Restores last pushed session (if any)
      - Throws away current session
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.session
      begin
        if cmd.expect?(NAME, "usage")
          if usage = session.usage
            session.renderer.info_with(
              "Current session usage: #{usage.total_tokens} tokens (prompt: #{usage.prompt_tokens}, completion: #{usage.completion_tokens}})")
          else
            session.renderer.info_with("No usage data for curent session at this time.")
          end
        elsif cmd.expect?(NAME, "reset")
          session.reset_session
        elsif cmd.expect?(NAME, "save", String)
          handle_session_save(session, cmd)
        elsif cmd.expect?(NAME, "load", String, tail: String?)
          handle_session_load(session, cmd)
        elsif cmd.expect?(NAME, "push",
                keep_tools: ["yes", "no", nil],
                keep_prompts: ["yes", "no", nil],
                keep_history: ["yes", "no", nil])
          handle_session_push(session_manager, cmd)
        elsif cmd.expect?(NAME, "pop")
          if session_manager.pop_session
            session.renderer.session_popped(depth: session_manager.depth)
          end
        else
          session.renderer.warning_with("ERROR: Unknown or incomplete sub-command: '#{cmd.input}'",
            help: HELP, markdown: true)
        end
      rescue e
        session.renderer.warning_with("ERROR: #{e.message}",
          help: HELP, markdown: true)
      end
    end

    private def handle_session_save(session, cmd)
      path = Path.new(cmd.arg_at(2).as(String))
      File.open(path, "w") do |file|
        session.save_session(file)
      end
      session.renderer.info_with("Session saved to JSONL file: #{path}")
    end

    private def handle_session_load(session, cmd)
      path = Path.new(cmd.arg_at(2).as(String))
      tail_n = cmd.arg_named?("tail").try(&.as(String).to_i) || -1
      session.renderer.info_with("Loading previously saved session: #{path}")
      File.open(path, "r") do |file|
        session.load_session(file, tail_num_chats: tail_n)
      end
    end

    private def handle_session_push(session_manager, cmd)
      keep_history = cmd.arg_named?("keep_history", "yes").try(&.!=("no"))
      keep_tools = cmd.arg_named?("keep_tools", "yes").try(&.!=("no"))
      keep_prompts = cmd.arg_named?("keep_prompts", "yes").try(&.!=("no"))
      session_manager.push_session(keep_history: keep_history, keep_tools: keep_tools, keep_prompts: keep_prompts)
      session_manager.session.renderer.session_pushed(depth: session_manager.depth,
        keep_history: keep_history, keep_tools: keep_tools, keep_prompts: keep_prompts)
    end
  end
end
