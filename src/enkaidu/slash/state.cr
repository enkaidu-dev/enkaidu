require "./command"

module Enkaidu::Slash
  class StateCommand < Command
    NAME = "/state"

    HELP_BRIEF = "`#{NAME} <sub-command>` - State management"

    HELP = <<-HELP1
      #{HELP_BRIEF}
      - `global (or g) namespaces (or ns)`
        - List namespaces in the global state
      - `global (or g) set ns=NAMESPACE key=KEY value=STR`
        - Set a global state key/value within the given namespace
      - `global (or g) get ns=NAMESPACE key=KEY`
        - Get a global state value for a key within the given namespace
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

    private def list_namespaces(session, namespaces)
      text = String.build do |io|
        if namespaces.empty?
          io.puts "- (None so far)"
        else
          namespaces.each do |name|
            io << "- `" << name << "`\n"
          end
        end
        io << '\n'
      end
      session.renderer.respond_with("List of global state namespaces:", text, markdown: true)
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.current.session

      if cmd.expect?(NAME, ["global", "g"], ["namespaces", "ns"])
        list_namespaces(session, session_manager.global_state.namespaces)
      elsif cmd.expect?(NAME, ["global", "g"], "set", ns: String, key: String, value: String)
        ns = cmd.arg_named("ns").as(String)
        key = cmd.arg_named("key").as(String)
        value = cmd.arg_named("value").as(String)
        session_manager.global_state.set(ns, key, value)
        session.renderer.respond_with("Updated. Namespace revision: #{session_manager.global_state.revision(ns)}")
      elsif cmd.expect?(NAME, ["global", "g"], "get", ns: String, key: String)
        ns = cmd.arg_named("ns").as(String)
        key = cmd.arg_named("key").as(String)
        value = session_manager.global_state.get?(ns, key) || "<unknown>"
        session.renderer.respond_with("#{key} = #{value}")
      else
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: #{cmd.arg_at? 0}",
          help: HELP, markdown: true)
      end
    end
  end
end
