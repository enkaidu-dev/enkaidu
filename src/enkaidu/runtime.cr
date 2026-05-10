require "./slash_commander"

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

    def session
      session_manager.current.session
    end

    def initialize(@options, @renderer)
      @session_manager = SessionManager.new(Session.new(renderer, opts: options))
      @commander = Slash::Commander.new(session_manager)

      # Always enable tools for
      # - spawning agent
      # - tools catalog
      session_manager.inject_function ListInstallableTools.new(self)
      session_manager.inject_function InstallToolsFunction.new(self)
      session_manager.inject_function SubAgentPromptFunction.new(self)

      # HACK ALERT
      # I don't like this; but for now I don't have a better way.
      # Revisit one day.
      session_manager.deploy_injected_functions(session)
    end

    def execute_query(query : String, &)
      query_queue = [query]
      in_macro = false
      while q = query_queue.shift?
        renderer.user_query_text(q, via_query_queue: true) if in_macro

        case q = q.strip
        when .starts_with?("!")
          if mac_queries = session.find_and_prepare_macro(q)
            # Expand the macro at the top of the queue, where
            # next query awaits; essentially inserting the macro
            query_queue.insert_all(0, mac_queries)
          end
          in_macro = true
          yield Event::Macro
        when .starts_with?("/")
          if commander.make_it_so(q) == :done
            yield Event::Done
          end
          yield Event::SlashCommand
        else
          session.ask(query: q,
            attach: commander.take_inclusions!,
            response_json_schema: commander.take_response_schema!)
          yield Event::Prompt
        end
      end
    rescue ex
      # Report unexpected exception and return back to the prompt so we can save / recover etc.
      renderer.error_with("ERROR: #{ex.inspect} (Report this please!)", markdown: false, help: ex.backtrace.join('\n'))
    end
  end
end
