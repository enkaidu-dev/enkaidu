require "cordon"

require "./slash_commander"
require "./runtime/*"

module Enkaidu
  class Error < Exception; end

  class Runtime
    enum Event
      Done
      SlashCommand
      Macro
      MacroBlock
      Prompt
    end

    getter session_manager : SessionManager
    getter commander : Slash::Commander
    getter renderer : SessionRenderer
    getter options : SessionOptions

    private getter conditional_helper = ConditionalCommandHelper.new
    private getter macro_helper

    def help_for_conditional(slash_command) : String?
      if slash_command == conditional_helper.name
        conditional_helper.help
      end
    end

    @conditional_command_names : Array(String)?

    def conditional_command_names : Array(String)
      @conditional_command_names ||= [conditional_helper.name]
    end

    @macro_cache = [] of String

    def macro_description(name) : String?
      if mac = (macro_helper.find_macro_by_name?(name) || macro_helper.find_macro_by_name?(name = name[1..-1]))
        "`!#{name}` - #{mac.description}"
      end
    end

    def macro_names : Array(String)
      if @macro_cache.size.zero?
        macro_helper.each_macro do |name, _mac, _origin|
          @macro_cache << "!#{name}"
        end
        @macro_cache.sort!
      end
      @macro_cache
    end

    def session
      session_manager.current.session
    end

    def macros
      macro_helper
    end

    def initialize(@options, @renderer)
      @session_manager = SessionManager.new(Session.new(renderer, opts: options))
      @macro_helper = MacroProcessingHelper.new(options)
      @commander = Slash::Commander.new(session_manager, macro_helper)

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
        if session_config.allow_shell_commands?
          session_manager.inject_function ShellCommandFunction.new(self)
        end
      end

      # HACK ALERT
      # I don't like this; but for now I don't have a better way.
      # Revisit one day.
      session_manager.deploy_injected_functions(session)
    end

    def cordon_policy : Cordon::Policy
      cordon_config = options.config.cordon

      # Setup initial policy defaults
      policy = Cordon::Policy.new
      cordon_config.policy.read_only_paths.each do |path|
        policy.read_only(path)
      end
      cordon_config.policy.read_write_paths.each do |path|
        policy.read_write(path)
      end

      # Pull in system preset
      policy = policy.merge(Cordon::Preset::System.for_current_platform)

      # Pull in additional presets based on environment options
      if ws = cordon_config.workspace
        using_brew = false
        if using_brew = ws.using_brew?
          policy = policy.merge(Cordon::Preset::Brew.for_current_platform)
        end

        if using_ruby = ws.using_ruby
          ruby_policy = cordon_ruby_policy(using_ruby, using_brew)
          if ruby_policy
            policy = policy.merge(ruby_policy)
          end
        end

        if using_python = ws.using_python
          py_policy = cordon_python_policy(using_python, using_brew)
          if py_policy
            policy = policy.merge(py_policy)
          end
        end
      end

      # Done
      policy
    end

    private def cordon_ruby_policy(using_ruby, using_brew)
      case using_ruby
      when true
        Cordon::Preset::Ruby.for_current_platform(with_brew: using_brew)
      when Config::Cordon::Workspace::UsingRuby
        Cordon::Preset::Ruby.for_executable(using_ruby.ruby_path)
      end
    end

    private def cordon_python_policy(using_python, using_brew)
      case using_python
      when true
        Cordon::Preset::Python.for_current_platform(with_brew: using_brew)
      when Config::Cordon::Workspace::UsingPython
        Cordon::Preset::Python.for_venv(using_python.venv_path)
      end
    end

    # Represents queued queries, and a string representation of the source of queries.
    # - For a macro, the source is the macro call
    # - For a user prompt, the source is USER_PROMPT.
    class QueuedQueries
      USER_PROMPT = "<user>"

      private getter prepared_macro : PreparedMacro

      def queries
        prepared_macro.queries
      end

      def source
        prepared_macro.invocation
      end

      # next query pointer indicating
      @next_query : Int32 = 0

      # Create one with user prompt
      def initialize(prompt : String)
        temp = [] of String | PreparedMacro
        temp << prompt
        @prepared_macro = PreparedMacro.new(prompt, temp)
      end

      # Create one with a macro
      def initialize(@prepared_macro)
      end

      # Return true if no more queries remain
      def finished?
        @next_query >= queries.size
      end

      # Force completion of macro, moving next query pointer to end
      def finish!
        @next_query = queries.size
      end

      # Return next query if any, or `nil` if at end of macro
      def next_query? : String | PreparedMacro?
        if q = queries[@next_query]?
          @next_query += 1
          return q
        end
      end

      # Restart the macro by resetting the next query pointer
      protected def restart!
        @next_query = 0
      end
    end

    alias QueryQueueStack = Array(QueuedQueries)

    private def query_queue_stack_trace(q : String?, qcurrent : QueuedQueries, qqs : QueryQueueStack, io : IO) : Void
      io.puts q if q
      count = qqs.size
      io << (count.zero? ? "  └─" : "  ├─") if q
      io.puts qcurrent.source
      qqs.reverse_each do |queued|
        count -= 1
        io << (count.zero? ? "  └─" : "  ├─")
        io.puts queued.source
      end
    end

    private def query_queue_stack_trace(q : String?, qcurrent : QueuedQueries, qqs : QueryQueueStack) : String
      String.build do |str_io|
        query_queue_stack_trace(q, qcurrent, qqs, str_io)
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
      q = nil
      begin
        while q = query_queue.next_query?
          if q.is_a? PreparedMacro
            _handle_nested_block
          elsif q.is_a? String
            _handle_prompt
          end
          # Check if query queue is empty, and pop from the query queue stack
          # to continue with next query in outer frame
          if query_queue.finished?
            # It's possible prior queues in stack are empty, so we need to unwind until
            # - either nothing is left
            # - or we get to a queue with items
            while !query_queue_stack.empty?
              # Replace current query queue with one we pushed last onto stack of queues
              query_queue = query_queue_stack.pop
              break unless query_queue.finished?
            end
          end
        end
      rescue ex
        # Report unexpected exception and return back to the prompt so we can save / recover etc.
        detail = String.build do |io|
          q = q.is_a?(PreparedMacro) ? "Prepared macro: #{q.invocation}" : q
          query_queue_stack_trace(q, query_queue, query_queue_stack, io)
          io.puts "---"
          ex.backtrace.each do |line|
            io.puts line
          end
        end
        renderer.error_with("ERROR: #{ex.inspect} (Report this please!)", markdown: false, help: detail)
      end
    end

    #
    # Macros used by the execution loop
    #

    # Handle nested macro blocks
    private macro _handle_nested_block
      # Push the current query queue on to the stack of queues
      # iff it's not already empty
      query_queue_stack << query_queue
      # make the macro's queries the current queue
      query_queue = QueuedQueries.new(q)
      yield Event::MacroBlock
    end

    # Handle prompt detection and delegate execution
    private macro _handle_prompt
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
    end

    # Handling code for `?...` commands
    private macro _execute_conditional_command_
      result = conditional_helper.handle_conditional_command(session_manager, q)
      case result[:continue]
      when .break?
        query_queue.finish! # skip remaining queries
        if msg = result[:message]
          renderer.respond_with(msg)
        end
      when .abort?
        trace = query_queue_stack_trace(q, query_queue, query_queue_stack)
        query_queue.finish! # skip remaining queries
        query_queue_stack.clear
        renderer.error_with(result[:message] || "ERROR: Aborting: Unknown reason.", trace)
      end # else `Yes` so continue
    end

    # Handling code for `!...` commands
    private macro _execute_macro_command_
      if prepared_macro = macro_helper.find_and_prepare_macro(q)
        # Push the current query queue on to the stack of queues
        # iff it's not already empty
        query_queue_stack << query_queue
        # make the macro's queries the current queue
        query_queue = QueuedQueries.new(prepared_macro)
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
  end
end
