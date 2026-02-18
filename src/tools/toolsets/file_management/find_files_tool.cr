require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::FileManagement
  # The `FindFilesTool` defines a tool that find and returns all files and folders that match a specific glob pattern.
  # It ensures the operation is performed securely within the allowed directory,
  # avoiding access to unauthorized paths.
  class FindFilesTool < BuiltInFunction
    name "find_files"

    # Provide a description for the tool
    description "Finds files and directories in a directory hierarchy by matching a glob pattern."

    # Define the acceptable parameter using the `param` method
    param "starting_path", required: false,
      description: "The starting point from which this tool looks for " \
                   "files and directories matching the path pattern. Defaults to \".\" if not" \
                   "specified."
    param "path_pattern", required: true,
      description: "The glob pattern expression with which to find matching files and directories. "
    param "max", type: Param::Type::Num, required: false,
      description: "Maxmimum number of matches to return (default is #{FileHelper::MAX_FIND_FILE_MATCHES})"
    param "sort", type: Param::Type::Bool, required: false,
      description: "Set to false to disable sorting (default is true)"

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        pattern = args["path_pattern"]?.try(&.as_s?) || return error_response("The required `path_pattern` was not specified")
        start = args["starting_path"]?.try(&.as_s?) || "."
        max = args["max"]?.try(&.as_i?) || MAX_FIND_FILE_MATCHES
        sort = args["sort"]?.try(&.as_bool?)
        sort = true if sort.nil?

        find_pattern = "#{start}/#{pattern}"

        unless within_current_directory?(resolve_path(find_pattern))
          return error_response("Looking outside current directory not allowed.")
        end

        if find_pattern.includes?("../") || find_pattern.includes?("/..")
          return error_response("Reverse path navigation (via `..`) not allowed.")
        end

        # Move the file to the deleted_files directory
        begin
          success_response(find_files(find_pattern, max, sort))
        rescue e
          error_response("An error occurred while finding file: #{e.message}")
        end
      end

      # Create a success response as a JSON string
      private def success_response(matches : Array(String))
        matches.to_json
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
