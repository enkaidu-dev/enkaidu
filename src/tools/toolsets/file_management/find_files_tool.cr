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
    param "pattern", required: true,
      description: "The glob pattern expression with which to find matching files. " \
                   "Supports wildcards `*`, globstars `**`, branching `{a,n}`, " \
                   "character ranges [a-z] and negated ranges [^a-z],"
    param "max", type: Param::Type::Num,
      description: "Optional, maxmimum number of matches to return (default is #{FileHelper::MAX_FIND_FILE_MATCHES})"
    param "sort", type: Param::Type::Bool,
      description: "Optional, set to false to disable sorting (default is true)"

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        pattern = args["pattern"]?.try(&.as_s?) || "*"
        max = args["max"]?.try(&.as_i?) || MAX_FIND_FILE_MATCHES
        sort = args["sort"]?.try(&.as_bool?)
        sort = true if sort.nil?

        unless within_current_directory?(resolve_path(pattern))
          return error_response("Looking outside current directory not allowed.")
        end

        if pattern.includes?("../") || pattern.includes?("/..")
          return error_response("Reverse path navigation (via `..`) not allowed.")
        end

        # Move the file to the deleted_files directory
        begin
          success_response(find_files(pattern, max, sort))
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
