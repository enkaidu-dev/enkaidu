require "./slash_commander"
require "./runtime/*"

module Enkaidu
  class Error < Exception; end

  class Runtime
    enum Event
      Done
      SlashCommand
      Macro
      Prompt
    end

    getter session_manager : SessionManager
    getter commander : Slash::Commander
    getter renderer : SessionRenderer
    getter options : SessionOptions

    private getter conditional_helper = ConditionalCommandHelper.new

    def help_for_conditional(slash_command) : String?
      if slash_command == conditional_helper.name
        conditional_helper.help
      end
    end

    @conditional_command_names : Array(String)?

    def conditional_command_names : Array(String)
      @conditional_command_names ||= [conditional_helper.name]
    end

    def session
      session_manager.current.session
    end

    def initialize(@options, @renderer)
      @session_manager = SessionManager.new(Session.new(renderer, opts: options))
      @commander = Slash::Commander.new(session_manager)

      # Inject system tools based on session configuration
      if session_config = options.config.session
        if session_config.allow_tool_discovery?
          session_manager.inject_function ListInstallableTools.new(self)
          session_manager.inject_function InstallToolsFunction.new(self)
        end
        if session_config.allow_sub_agents?
          session_manager.inject_function SubAgentPromptFunction.new(self)
        end
        if session_config.allow_global_state?
          session_manager.inject_function GlobalStateGetFunction.new(self)
          session_manager.inject_function GlobalStateSetFunction.new(self)
        end
      end

      # HACK ALERT
      # I don't like this; but for now I don't have a better way.
      # Revisit one day.
      session_manager.deploy_injected_functions(session)
    end

    # Represents queued queries, and a string representation of the source of queries.
    # - For a macro, the source is the macro call
    # - For a user prompt, the source is USER_PROMPT.
    class QueuedQueries
      USER_PROMPT = "<user>"

      getter source : String
      getter queries : Array(String)

      # Create one with user prompt
      def initialize(prompt : String)
        @source = USER_PROMPT
        @queries = [prompt]
      end

      # Create one with a macro
      def initialize(macro_call : String, @queries)
        @source = macro_call
      end
    end

    alias QueryQueueStack = Array(QueuedQueries)

    #
    # Macros used by the execution loop
    #

    # Handling code for `?...` commands
    private macro _execute_conditional_command_
      result = conditional_helper.handle_conditional_command(session_manager, q)
      case result[:continue]
      when .break?
        query_queue.queries.clear # Empty the current queue
        if msg = result[:message]
          renderer.respond_with(msg)
        end
      when .abort?
        trace = query_queue_stack_trace(query_queue, query_queue_stack)
        query_queue.queries.clear # Empty the current queue
        query_queue_stack.clear
        renderer.error_with(result[:message] || "ERROR: Aborting: Unknown reason.", trace)
      end # else `Yes` so continue
    end

    # Handling code for `!...` commands
    private macro _execute_macro_command_
      if mac_queries = session.find_and_prepare_macro(q)
        # Push the current query queue on to the stack of queues
        # iff it's not already empty
        query_queue_stack << query_queue # unless query_queue.queries.empty?
        # make the macro's queries the current queue
        query_queue = QueuedQueries.new(q, mac_queries)
        in_macro = true
        yield Event::Macro
      else
        renderer.error_with("ERROR: Aborting: Unknown macro: #{q}")
        break
      end
    end

    # Handling code for `/...` commands
    private macro _execute_slash_command_
      if commander.make_it_so(q) == :done
        yield Event::Done
      end
      yield Event::SlashCommand
    end

    private def query_queue_stack_trace(qcurrent : QueuedQueries, qqs : QueryQueueStack, io : IO) : Void
      io.puts qcurrent.source
      count = qqs.size
      qqs.reverse_each do |queued|
        count -= 1
        io << (count.zero? ? "  └─" : "  ├─")
        io.puts queued.source
      end
    end

    private def query_queue_stack_trace(qcurrent : QueuedQueries, qqs : QueryQueueStack) : String
      String.build do |str_io|
        query_queue_stack_trace(qcurrent, qqs, str_io)
      end
    end

    def execute_query(prompt : String, &)
      # Maintain a stack of query queues; when marcos are invoked,
      # push current query queue onto stack and use the macro's queries as
      # current quuery queue.
      # Why? In effect the current query queue is the "frame" for the currently running macro.
      # This should allow us to support, for e.g., a `?break_if CONDITION`
      # command that aborts current macro and continue with the one that
      # called it.
      query_queue_stack = QueryQueueStack.new
      # Current command or commands (if macro invoked)
      query_queue = QueuedQueries.new(prompt)
      # Track when macro is invoked
      in_macro = false
      begin
        while q = query_queue.queries.shift?
          renderer.user_query_text(q, via_query_queue: true) if in_macro

          case q = q.strip
          when .starts_with?("?")
            _execute_conditional_command_
          when .starts_with?("!")
            _execute_macro_command_
          when .starts_with?("/")
            _execute_slash_command_
          else
            session.ask(query: q,
              attach: commander.take_inclusions!,
              response_json_schema: commander.take_response_schema!)
            yield Event::Prompt
          end
          # Check if query queue is empty, and pop from the query queue stack
          # to continue with next query in outer frame
          if query_queue.queries.empty?
            # It's possible prior queues in stack are empty, so we need to unwind until
            # - either nothing is left
            # - or we get to a queue with items
            while !query_queue_stack.empty?
              # Replace current query queue with one we pushed last onto stack of queues
              query_queue = query_queue_stack.pop
              break unless query_queue.queries.empty?
            end
          end
        end
      rescue ex
        # Report unexpected exception and return back to the prompt so we can save / recover etc.
        detail = String.build do |io|
          query_queue_stack_trace(query_queue, query_queue_stack, io)
          io.puts "---"
          ex.backtrace.each do |line|
            io.puts line
          end
        end
        renderer.error_with("ERROR: #{ex.inspect} (Report this please!)", markdown: false, help: detail)
      end
    end
  end
end
