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

    def push_session(keep_tools = true, keep_prompts = true, keep_history = true,
                     system_prompt_name : String? = nil) : Nil
      @session_stack.push Session.new(fork_from: session,
        keep_tools: keep_tools,
        keep_prompts: keep_prompts,
        keep_history: keep_history,
        system_prompt_name: system_prompt_name)
    end

    def pop_session(transfer_last_num = 0, filter_by_role : String? = nil, reset_parent = false, &) : Bool
      if @session_stack.size > 1
        prev = @session_stack.pop
        yield true # Notify to indicate we're back in the parent session
        session.reset_session(nil) if reset_parent
        if transfer_last_num.positive?
          prev.transfer_tail_chats(to: session, num: transfer_last_num,
            filter_by_role: filter_by_role)
        end
        return true
      end
      false
    end
  end
end
