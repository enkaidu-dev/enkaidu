require "json"

require "../tools"

# The `ShellCommandTool` class defines a tool for executing shell commands within the
# current project directory. Note: This implementation assumes a protected environment (e.g., chroot).
class ShellCommandTool < LLM::LocalFunction
  class PermissionError < Exception; end

  class SafetyError < Exception; end

  ALLOWED_COMMANDS  = ["ls", "cat", "grep", "whoami", "file", "wc", "find"]
  UNSAFE_CHARACTERS = ['|', '<', '>', ';', '&']

  name "shell_command"

  # Provide a description for the tool
  description "Executes one of the allowed shell commands (
    #{ALLOWED_COMMANDS.join(", ")} within the current project's root directory and
    returns the shell command's output."

  # Define the acceptable parameter using the `param` method
  param "command", type: LLM::ParamType::Str, description: "The shell command to execute.", required: true

  runner Runner

  # The Runner class executes the function
  class Runner < LLM::Function::Runner
    def execute(args : JSON::Any) : String
      command = args["command"].as_s? || return error_response("The required 'command' was not specified.")

      begin
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
      unless ALLOWED_COMMANDS.any? { |cmd| command.index("#{cmd} ") == 0 }
        raise SafetyError.new("Only the following commands are allowed: #{ALLOWED_COMMANDS.join(", ")}.")
      end

      unsafe_characters.each do |char|
        raise SafetypError.new("The following characters are not allowed: #{UNSAFE_CHARACTERS.join(", ")}") if command.includes?(char)
      end

      true
    end

    def requires_confirmation?(command)
      true
    end

    def user_confirms?(command)
      puts "The assistant wants to run the following command:\n\n"
      puts "> #{command}\n\n".colorize(:red).bold
      print "Allow? [y/N] "
      response = STDIN.raw &.read_char
      puts response

      ['y', 'Y'].includes?(response)
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
