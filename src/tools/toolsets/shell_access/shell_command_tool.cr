require "json"
require "../../built_in_function"

module Tools::ShellAccess
  # The `ShellCommandTool` class defines a tool for executing shell commands within the
  # current project directory. Note: This implementation assumes a protected environment (e.g., chroot).
  class ShellCommandTool < BuiltInFunction
    # The `PermissionError` class is raised when user permission is required and denied for executing a command.
    class PermissionError < Exception; end

    # The `SafetyError` class is used to indicate that a command is unsafe for execution due to its content.
    class SafetyError < Exception; end

    UNSAFE_STRINGS = ["..", "|", "<", ">", ";", "&"]

    @allowed_cmds : Array(String)? = nil
    @approved_cmds : Array(String)? = nil

    # Allowed commands can be specified via tool settings in the config file, or
    # via `ENKAIDU_ALLOWED_EXECUTABLES` environment variable, with config taking priority.
    # Approved commands are includes in the allowed commands list.
    def allowed_commands : Array(String)
      @allowed_cmds ||= approved_commands |
                        case value = (settings.try &.["allowed_commands"]?)
                        when Array(String) then value
                        when String        then [value]
                        else
                          ENV.fetch("ENKAIDU_ALLOWED_EXECUTABLES", "ls cat grep whoami file wc find").split(" ")
                        end
    end

    # Approved commands can be specified via tool settings in the config file, or
    # via `ENKAIDU_APPROVED_EXECUTABLES` environment variable, with config taking priority.
    def approved_commands : Array(String)
      @approved_cmds ||= case value = (settings.try &.["approved_commands"]?)
                         when Array(String) then value
                         when String        then [value]
                         else
                           ENV.fetch("ENKAIDU_APPROVED_EXECUTABLES", nil).try(&.split(" ")) || [] of String
                         end
    end

    name "shell_command"

    # Provide a description for the tool
    static_description "Executes one of the allowed shell commands from within the " \
                       "current project's root directory and returns the shell command's output."

    runtime_description "Executes one of the following allowed shell commands from within the " \
                        "current project's root directory and returns the shell command's output: " \
                        "#{allowed_commands.join(", ")}"

    # Define the acceptable parameter using the `param` method
    param "command", type: Param::Type::Str,
      description: "The shell command to execute.", required: true

    # Replace `runner` macro to create with self
    def new_runner : Runner
      Runner.new(self)
    end

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      private getter func : ShellCommandTool

      def initialize(@func); end

      def execute(args : JSON::Any) : String
        command = args["command"].as_s? || return error_response("The required 'command' was not specified.")

        begin
          check_safety(command)

          if requires_confirmation?(command)
            raise PermissionError.new("User denied execution.") unless user_confirms?(command)
          end

          output = `#{command} 2>&1`
          success_response(command, output)
        rescue e
          error_response("An error occurred while executing the command: #{e.message}")
        end
      end

      def check_safety(command)
        unless func.allowed_commands.any? { |cmd| command.index("#{cmd} ") == 0 }
          if command.split(' ', 2).size == 1
            raise SafetyError.new("The `#{command}` command must specify arguments. Bare commands not allowed yet.")
          else
            raise SafetyError.new("Only the following commands are allowed: #{func.allowed_commands.join(", ")}.")
          end
        end

        UNSAFE_STRINGS.each do |str|
          if command.includes?(str)
            raise SafetyError.new("The following strings are not allowed: #{UNSAFE_STRINGS.join(", ")}")
          end
        end

        true
      end

      def requires_confirmation?(command)
        if (name = command.split(' ', 2).first) && func.approved_commands.includes?(name)
          false
        else
          true
        end
      end

      def user_confirms?(command)
        func.renderer.user_confirm_shell_command?(command)
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
