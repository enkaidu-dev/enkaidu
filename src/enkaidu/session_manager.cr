require "./session_stack"

module Enkaidu
  # Manager a stack of sessions
  class SessionManager
    @stacks = {} of String => SessionStack

    getter current : SessionStack

    def initialize(session : Session)
      @current = SessionStack.new("prime", session)
      @stacks[current.name] = current
    end

    # Creates a new named session stack and switches to it
    def new_session_stack(name : String, &)
      raise ArgumentError.new("Session stack already exist with that name: #{name}") if has_session_stack?(name)

      curr_session = current.session
      session = Session.new(curr_session.renderer, curr_session.opts)
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

    def each(&)
      @stacks.each do |name, stack|
        yield name, stack
      end
    end
  end
end
