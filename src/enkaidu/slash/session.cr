require "./command"

module Enkaidu::Slash
  class SessionCommand < Command
    NAME = "/session"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `ls`
      - List all available session named sessions
    - `goto <NAME>`
      - Switch to an active named session.
    - `new <NAME> [model=name]`
      - Create a new named session and switch to it immediately
      - Optionally specify a model name from the config to use for the new session
    - `usage`
      - Show the token usage / size for the current chat session based on
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
    - `reset [system_prompt_name=name]`
      - Clear all active tools and MCP connections from the current chat session
      - Throws away the current session / context
      - Auto loads tools and MCP connections in the configuration
      - Replaces the system prompt referenced by name if specified
    - `push [keep_tools=yes|no] [keep_prompts=yes|no] [keep_history=yes|no] [system_prompt_name=NAME]`
      - Push current chat session onto session stack and fork a new chat session, keeping tools, prompts, and history as specified
      - Switches the system prompt if the name of a system prompt template is provided
      - By default the new session keeps all state
    - `pop`
      - Throws away current chat session and restore last pushed (parent) chat session (if any)
    - `pop_and_take [response_only=yes|no] [reset_parent=yes|no]`
      - Throws away current chat session and restore last pushed (parent) chat session (if any), with following caveats:
        - Resets the restored session if `reset_parent=yes` is specified
        - Appends the last chat from the interim session, keeping the both the query and response unless
        `response_only=yes` is specified, in which case only the response is kept.
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    YES_NO_NIL = ["yes", "no", nil]

    def handle(session_manager : SessionManager, cmd : CommandParser)
      case cmd
      when .expect?(NAME, ["ls", "usage", "pop"])   then handle_bare_commands(session_manager, cmd)
      when .expect?(NAME, ["goto", "save"], String) then handle_one_string_commands(session_manager, cmd)
      else
        handle_compound_commands(session_manager, cmd)
      end
    rescue e
      session_manager.current.session.renderer.warning_with("ERROR: #{e.message}",
        help: HELP, markdown: true)
    end

    private def handle_bare_commands(session_manager, cmd)
      case cmd.arg_at(1).as(String)
      when "ls"    then handle_stack_list(session_manager)
      when "usage" then handle_session_usage(session_manager.current.session)
      when "pop"   then handle_session_pop(session_manager.current)
      end
    end

    private def handle_one_string_commands(session_manager, cmd)
      case cmd.arg_at(1).as(String)
      when "goto" then handle_stack_goto(session_manager, cmd)
      when "save" then handle_session_save(session_manager.current.session, cmd)
      end
    end

    private def handle_compound_commands(session_manager, cmd)
      current_session_stack = session_manager.current
      session = current_session_stack.session
      case cmd
      when .expect?(NAME, "load", String, tail: String?)        then handle_session_load(session, cmd)
      when .expect?(NAME, "reset", system_prompt_name: String?) then handle_session_reset(session, cmd)
      when .expect?(NAME, "new", String, model: String?)
        handle_stack_new(session_manager, cmd)
      when .expect?(NAME, "push", system_prompt_name: String?,
        keep_tools: YES_NO_NIL, keep_prompts: YES_NO_NIL, keep_history: YES_NO_NIL)
        handle_session_push(current_session_stack, cmd)
      when .expect?(NAME, "pop_and_take",
        response_only: YES_NO_NIL, reset_parent: YES_NO_NIL)
        handle_session_pop_take(current_session_stack, cmd)
      else
        session.renderer.warning_with("ERROR: Unknown or incomplete sub-command: '#{cmd.input}'",
          help: HELP, markdown: true)
      end
    end

    private def handle_stack_new(session_manager, cmd)
      entry_session = session_manager.current.session
      name = cmd.arg_at?(2).as(String)
      model_name = cmd.arg_named?("model").try(&.as(String))

      if session_manager.has_session_stack?(name)
        entry_session.renderer.error_with("ERROR: Another session exist with that name: #{name}")
      else
        session_manager.new_session_stack(name, model_name) do |session|
          session.renderer.session_stack_new(name)
        end
      end
    end

    private def handle_stack_goto(session_manager, cmd)
      current_session_stack = session_manager.current
      name = cmd.arg_at?(2).as(String)
      if current_session_stack.name == name
        session_manager.current.session.renderer.info_with("INFO: No change to session stack: #{name}")
        session_manager.current.session.renderer.session_stack_changed(name)
      else
        if session_manager.has_session_stack?(name)
          session_manager.goto_session_stack(name)
          session_manager.current.session.renderer.session_stack_changed(name)
        else
          session_manager.current.session.renderer.info_with("ERROR: Unknown session stack: #{name}")
        end
      end
    end

    private def handle_stack_list(session_manager)
      current_session_stack = session_manager.current
      content = String.build do |str|
        session_manager.each do |name, stack|
          current = stack == current_session_stack
          str << "* "
          if current
            str << "**`" << name << "`**"
          else
            str << "`" << name << "`"
          end
          str << " _depth:_ `#{stack.depth}`" if stack.depth > 1
          str << " _model:_ `#{stack.session.chat.model}`"
          if current
            str << " <-- _(current)_"
          end
          str.puts
        end
      end
      current_session_stack.session.renderer.info_with("INFO: Active session stacks by name:",
        help: content, markdown: true)
    end

    private def handle_session_usage(session)
      if usage = session.usage
        session.renderer.info_with(
          "Current session usage: #{usage.total_tokens} tokens (prompt: #{usage.prompt_tokens}, completion: #{usage.completion_tokens}})")
      else
        session.renderer.info_with("No usage data for curent session at this time.")
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

    private def handle_session_reset(session, cmd)
      session.reset_session(sys_prompt: cmd.arg_named?("system_prompt_name").try(&.as(String)))
    end

    private def handle_session_pop(session_stack)
      session_stack.pop_session do
        session_stack.session.renderer.session_popped(depth: session_stack.depth)
      end
    end

    private def handle_session_pop_take(session_stack, cmd)
      filter_role = cmd.arg_named?("response_only", "no").try(&.==("yes")) ? "assistant" : nil
      reset_parent = cmd.arg_named?("reset_parent", "no").try(&.!=("no"))
      session_stack.pop_session(transfer_last_num: 1, filter_by_role: filter_role, reset_parent: reset_parent) do
        # Render session popped
        session_stack.session.renderer.session_popped(depth: session_stack.depth)
      end
    end

    private def handle_session_push(session_stack, cmd)
      sys_prompt_name = cmd.arg_named?("system_prompt_name").try(&.as(String))
      keep_history = cmd.arg_named?("keep_history", "yes").try(&.!=("no"))
      keep_tools = cmd.arg_named?("keep_tools", "yes").try(&.!=("no"))
      keep_prompts = cmd.arg_named?("keep_prompts", "yes").try(&.!=("no"))
      session_stack.push_session(keep_history: keep_history, keep_tools: keep_tools, keep_prompts: keep_prompts,
        system_prompt_name: sys_prompt_name)
      session_stack.session.renderer.session_pushed(depth: session_stack.depth,
        keep_history: keep_history, keep_tools: keep_tools, keep_prompts: keep_prompts)
    end
  end
end
