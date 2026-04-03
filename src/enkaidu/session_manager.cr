require "./session_stack"

module Enkaidu
  # Manager a stack of sessions
  class SessionManager
    @stacks = {} of String => SessionStack

    getter current : SessionStack

    # The app / runtime can inject tools that are available to all sessions
    protected getter injected_tools = [] of LLM::LocalFunction

    def initialize(session : Session)
      @current = SessionStack.new("prime", session)
      @stacks[current.name] = current
    end

    # Inject functions / tools that will be available in all sessions
    def inject_function(tool : LLM::LocalFunction)
      injected_tools << tool
    end

    def deploy_injected_functions(session)
      # Always enable tool for scheduling a prompt for Enkaidu.
      injected_tools.each do |tool|
        session.chat.with_tool(tool)
      end
    end

    # Creates a new named session stack and switches to it
    def new_session_stack(name : String, model_name : String?, &)
      raise ArgumentError.new("Session stack already exist with that name: #{name}") if has_session_stack?(name)

      curr_session = current.session
      session = Session.new(curr_session.renderer, curr_session.opts,
        unique_model_name: model_name)
      deploy_injected_functions(session)
      @stacks[name] = SessionStack.new(name, session)
      yield session
      goto_session_stack(name)
      session.auto_load
    end

    def has_session_stack?(name : String)
      @stacks.has_key? name
    end

    def goto_session_stack(name : String)
      @current = @stacks[name]
    end

    # Push a session in current stack, make a query, and then extract the session outline
    # before popping the session. Return the extracted session as a JSON string,
    # or `nil` on error.
    def ask_forked_session(query : String, keep_history = false) : String?
      stack = current
      stack.push_session(keep_history: keep_history,
        keep_tools: true, keep_prompts: true)
      session = stack.session
      session.renderer.session_pushed(depth: stack.depth, keep_history: keep_history,
        keep_tools: true, keep_prompts: true)
      session.ask(query)
      extract = session.chat.extract_conversations(LLM::Conversation::SessionOuter)
      stack.pop_session(SessionStack::Retain::None) do
        session.renderer.session_popped(depth: stack.depth)
      end
      extract
    end

    def each(&)
      @stacks.each do |name, stack|
        yield name, stack
      end
    end
  end
end
