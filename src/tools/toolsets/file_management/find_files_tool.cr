require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::FileManagement
  # The `FindFilesTool` defines a tool that find and returns all files and folders that match a specific glob pattern.
  # It ensures the operation is performed securely within the allowed directory,
  # avoiding access to unauthorized paths.
  class FindFilesTool < BuiltInFunction
    name "find_files"
    side_effects SideEffects::FileRead | SideEffects::DirRead

    # Provide a description for the tool
    description "Finds files and directories at `path` matching the glob `expression` (the tool looks up 'path/expression'), " \
                "and returns a JSON array of matching paths; an empty array means nothing matched — broaden the glob (use ** for subdirectories) before re-trying. " \
                "Example: to list all Crystal files under src, use path=\"src\" and expression=\"**/*.cr\"."

    # Define the acceptable parameter using the `param` method
    param "expression", required: true,
      description: "The glob pattern expression with which to find matching files and directories, relative to `path`, e.g. \"*.cr\" or \"tools/**/*.cr\". A single * is not recursive; use ** to recurse."
    param "path", required: true,
      description: "The base directory inside which this tool looks for files and directories; it is combined with `expression` to form `path/expression`, so do not repeat `path` inside `expression`."
    param "max", type: Param::Type::Num, required: false,
      description: "Optional. Maximum number of matches to return (default is #{FileHelper::MAX_FIND_FILE_MATCHES})"
    param "sort", type: Param::Type::Bool, required: false,
      description: "Optional. Set to false to disable sorting (default is true)"

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        pattern = args["expression"]?.try(&.as_s?) || return error_response("The required glob `expression` was not specified")
        path = args["path"]?.try(&.as_s?).try(&.strip) || return error_response("The required starting directory `path` was not specified")

        return error_response("The required `path` must not be empty") if path.empty?

        max = args["max"]?.try(&.as_i?) || MAX_FIND_FILE_MATCHES
        sort = args["sort"]?.try(&.as_bool?)
        sort = true if sort.nil?

        find_pattern = "#{path}/#{pattern}"

        unless within_current_directory?(resolve_path(find_pattern))
          return error_response("Looking outside current directory not allowed.")
        end

        if find_pattern.includes?("../") || find_pattern.includes?("/..")
          return error_response("Reverse path navigation (via `..`) not allowed.")
        end

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
