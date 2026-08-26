require "json"
require "cordon"
require "./session_built_in_function"

module Enkaidu
  # This is the Enkaidu shell command function with session-levelc configuration.
  class ShellCommandFunction < SessionBuiltInFunction
    # The `PermissionError` class is raised when user permission is required and denied for executing a command.
    class PermissionError < Exception; end

    # The `SafetyError` class is used to indicate that a command is unsafe for execution due to its content.
    class SafetyError < Exception; end

    # Forbidden strings cause commands to fail
    # Restricted strings always require confirmation

    {% if flag?(:windows) %}
      # In Windows commands, & is unconditional separate, like ';' in Linux. Don't forbid.
      FORBIDDEN_STRINGS  = ["..", "<", ">"]
      MULTI_CMD_SPLIT_RX = /(?:\|\|)|(?:&&)|[;|&]/
      ALWAYS_RESTRICTED  = ["rm", "del", "eval", "for", "--expression", "-e ", "-e=", "|", ";"].map(&.upcase)
    {% else %}
      # In *nix commands, & is for background execution, so we forbid it.
      FORBIDDEN_STRINGS  = ["..", "&"]
      MULTI_CMD_SPLIT_RX = /(?:\|\|)|(?:&&)|[;|]/
      ALWAYS_RESTRICTED  = ["rm", "eval", "$(", "--expression", "-e ", "-e=", "|", ";"].map(&.upcase)
    {% end %}

    enum CordonHow
      None
      ReadOnly
      ReadWrite
    end

    @allowed_cmds : Array(String)? = nil
    @approved_cmds : Array(String)? = nil
    @restricted_terms : Array(String)? = nil

    # -----
    # Approved and Allowed commands are tested as prefixes. This allows allowed commands to include
    # subcommands. Note that a command must match one of the allowed/approved command prefixes EXACTLY
    # or the command MUST BEGIN WITH allowed/approved command PLUS A SPACE.
    #
    # i.e. if "crystal" is allowed, it must be called exactly `cmd == "crystal"` or
    # must match the start with a subsequent space `cmd.starts_with?("crystal ")`
    # -----

    # Allowed commands can be specified via tool settings in the config file, or
    # via `ENKAIDU_ALLOWED_EXECUTABLES` environment variable, with config taking priority.
    # Approved commands are includes in the allowed commands list.
    def allowed_commands : Array(String)
      @allowed_cmds ||= approved_commands |
                        extract_setting("allowed_commands", "ENKAIDU_ALLOWED_EXECUTABLES", "grep whoami file wc")
    end

    # Approved commands can be specified via tool settings in the config file, or
    # via `ENKAIDU_APPROVED_EXECUTABLES` environment variable, with config taking priority.
    def approved_commands : Array(String)
      @approved_cmds ||= extract_setting("approved_commands", "ENKAIDU_APPROVED_EXECUTABLES")
    end

    # Additional restricted terms can be specified via tool settings in the config file.
    # Commands are checked if they are present ANYWHERE within.
    def restricted_terms : Array(String)
      @restricted_terms ||= ALWAYS_RESTRICTED |
                            extract_setting("restricted_terms", "ENKAIDU_RESTRICTED_TERMS")
    end

    # Returns CordonHow for how commands should run cordoned off
    def run_with_cordon : CordonHow
      config = runtime.options.config
      case config.cordon.mode
      when .commands?
        # In Command mode, though, use readonly? flag to decide
        # how to use the cordon
        if config.session.try(&.readonly?)
          CordonHow::ReadOnly
        else
          CordonHow::ReadWrite
        end
      else
        # Do not run commands within a cordon in Unsafe and Agent modes
        CordonHow::None
      end
    end

    # Retrieve a setting if present, or env variable if present, or default if specified
    private def extract_setting(name, env_fallback, default : String? = nil)
      case value = (settings.try &.[name]?)
      when Array(String) then value
      when String        then [value]
      else
        ENV.fetch(env_fallback, default).try(&.split(" ")) || [] of String
      end
    end

    # Returns true if "skip_confirm_with_cordon" is true.
    def skip_confirm_with_cordon? : Bool
      settings.try(&.["skip_confirm_with_cordon"]?) == true
    end

    # Returns true if "execute_through_shell" is true.
    def execute_through_shell? : Bool
      settings.try(&.["execute_through_shell"]?) == true
    end

    name "shell_command"

    # Don't know what the chell command does, so assume anything is possible
    side_effects SideEffects::CommandExec

    COMMON_DESCRIPTION = "Executes one of the allowed shell commands from within the " \
                         "current project's directory and returns the shell command's output." \
                         "Commands with restricted terms always require approval."
    # Provide a description for the tool
    static_description <<-DESC
    #{COMMON_DESCRIPTION}
    DESC

    runtime_description <<-DESC
    #{COMMON_DESCRIPTION}

    CONSTRAINTS:
    - Allowed commands: #{allowed_commands.join(", ")}
    #{unless run_with_cordon.none?
        "- Cordon (sandbox) mode: #{run_with_cordon}"
      end}
    #{if execute_through_shell?
        "- Execute commands through shell: Enabled"
      end}
    DESC

    # Define the acceptable parameter using the `param` method
    param "command", type: Param::Type::Str, required: true,
      description: "The shell command to execute."

    # Replace `runner` macro to create with self
    def new_runner : Runner
      Runner.new(self)
    end

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      private getter func : ShellCommandFunction

      def initialize(@func); end

      def execute(args : JSON::Any) : String
        command = args["command"]?.try(&.as_s?) || return error_response("The required 'command' was not specified.")
        command = command.strip
        return error_response("The required 'command' was empty.") if command.empty?

        begin
          # Split multiple commands if any so we can check each
          # Non-Windows: && splitting won't work for now since & is forbidden
          multi_commands = command.split(MULTI_CMD_SPLIT_RX).map(&.strip)
          # Make sure each command if safe
          multi_commands.each { |cmd| check_safety(cmd) }
          # Determine if we run with or without cordon
          run_without_cordon = func.run_with_cordon.none?

          # gather up any restricted terms and unapproved commands needing confirmation
          found_restricted = restricted_terms_in(command)
          found_unconfirmed = multi_commands.select { |cmd| requires_confirmation?(cmd) }

          # Confirm for restricted / not approved commands IF
          #   - running without cordon, OR
          #   - running with cordon AND not asked to skip confirm with cordon
          if run_without_cordon || !func.skip_confirm_with_cordon?
            # do any of the commands require confirmation?
            unless found_restricted.empty? && found_unconfirmed.empty?
              unless user_confirms?(command, found_restricted)
                raise PermissionError.new(<<-DENIED)
                User denied execution of command because:
                #{"- restricted terms found: #{found_restricted}" unless found_restricted.empty?}
                #{"- not pre-approved commands found: #{found_unconfirmed}" unless found_unconfirmed.empty?}
                DENIED
              end
            end
          else
            unless found_restricted.empty? && found_unconfirmed.empty?
              func.runtime.renderer.warning_with("WARNING: Skipping necessary shell command user confirmation by your request")
            end
          end

          # Now we can execute the command
          result = if run_without_cordon
                     run_command(command)
                   else
                     run_cordoned_command(command)
                   end
          success_response(command, result) # output)
        rescue e
          error_response("An error occurred while executing the command: #{e.message}")
        end
      end

      def run_command(cmd)
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = if func.execute_through_shell?
                   Process.run(cmd,
                     shell: true,
                     output: stdout,
                     error: stderr
                   )
                 else
                   argv = Process.parse_arguments(cmd)
                   Process.run(
                     argv[0],
                     argv[1..],
                     output: stdout,
                     error: stderr
                   )
                 end
        {exit_code: status.exit_code, stdout: stdout.to_s, stderr: stderr.to_s}
      end

      def run_cordoned_command(cmd)
        cmd_policy = Cordon::Policy.build do |policy|
          case func.run_with_cordon
          when .read_only?
            policy.read_only Dir.current
          when .read_write?
            policy.read_write Dir.current
          end
          policy.allow_network = false # deny all network access
          policy.working_dir = Dir.current
        end
        if runtime_policy = func.runtime.cordon_policy
          cmd_policy = cmd_policy.merge(runtime_policy)
        end
        result = if func.execute_through_shell?
                   Cordon.run([cmd], cmd_policy, shell: true)
                 else
                   argv = Process.parse_arguments(cmd)
                   Cordon.run(argv, cmd_policy)
                 end
        {exit_code: result.exit_code, stdout: result.stdout, stderr: result.stderr}
      end

      def check_safety(command)
        # MUST prefix-match
        unless func.allowed_commands.any? { |cmd| command == cmd || command.starts_with?("#{cmd} ") }
          raise SafetyError.new("Only the following commands are allowed: #{func.allowed_commands.join(", ")}.")
        end

        if FORBIDDEN_STRINGS.any? { |str| command.includes?(str) }
          raise SafetyError.new("The command contains some of the following forbidden strings: #{FORBIDDEN_STRINGS.join(", ")}")
        end

        # Command matches allowed list, and contains no unsafe strings
        true
      end

      # Returns all restricted terms (array of strings) found in the command
      def restricted_terms_in(command) : Array(String)
        cmd = command.upcase
        # check case insensitively
        func.restricted_terms.select { |term| cmd.includes?(term) }
      end

      def requires_confirmation?(command)
        if func.approved_commands.any? { |cmd| command == cmd || command.starts_with?("#{cmd} ") }
          # And approved command detected
          return false # good to go
        end
        # Confirmation required
        true
      end

      def user_confirms?(command, found_restricted)
        has_restricted = " AND contains restricted terms: #{found_restricted.join(", ")}" unless found_restricted.empty?
        banner = if func.run_with_cordon.none?
                   {
                     safe:    false,
                     message: "UNSAFE command execution, cordon not enabled!",
                   }
                 else
                   {
                     safe:    true,
                     message: "SAFE command execution, cordon enabled.",
                   }
                 end

        func.runtime.renderer.user_confirm_security_question?(
          description: "The agent's AI model wants to run the following system command#{has_restricted || ""}",
          subject: command,
          banner: banner
        )
      end

      # Create a success response as a JSON string
      def success_response(command, output)
        {
          command: command,
          output:  output,
        }.to_json
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
