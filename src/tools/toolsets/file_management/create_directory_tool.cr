require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::FileManagement
  # The `CreateDirectoryTool` class defines a tool for creating directories.
  # It ensures that the directory is created within the current working
  # directory and does not allow creation of paths that escape the root.
  class CreateDirectoryTool < BuiltInFunction
    name "create_directory"

    description "Creates a new directory at the specified relative path. " +
                "The operation is restricted to remain inside the current working directory."

    param "directory_path", type: LLM::ParamType::Str,
      description: "The relative path of the directory to create.", required: true

    runner Runner

    # The `Runner` class executes the logic to create directories within the specified constraints.
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        dir_path = args["directory_path"].as_s? || return error_response("The required directory_path was not specified")
        resolved_path = resolve_path(dir_path)

        # Ensure the path stays within the current working directory
        unless within_current_directory?(resolved_path)
          return error_response("The specified path '#{dir_path}' is outside the allowed directory.")
        end

        begin
          Dir.mkdir_p(resolved_path)
          success_response(dir_path)
        rescue e
          error_response("Failed to create directory: #{e.message}")
        end
      end

      private def error_response(message)
        {"error" => message}.to_json
      end

      private def success_response(directory_path)
        {directory_path: directory_path, status: "created"}.to_json
      end
    end
  end
end
