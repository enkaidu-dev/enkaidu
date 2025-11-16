require "./session"

module Enkaidu
  # Manager a stack of sessions
  class SessionManager
    @session_stack = [] of Session

    def initialize(session : Session)
      @session_stack.push session
    end

    def session
      @session_stack.last
    end

    def depth
      @session_stack.size
    end

    def push_session(keep_tools = true, keep_prompts = true, keep_history = true) : Nil
      @session_stack.push Session.new(fork_from: session,
        keep_tools: keep_tools,
        keep_prompts: keep_prompts,
        keep_history: keep_history)
    end

    def pop_session : Bool
      if @session_stack.size > 1
        @session_stack.pop
        return true
      end
      false
    end
  end
end
