require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::FileManagement
  # The `RenameFileTool` class defines a tool to rename and/or move a file in the current directory.
  # It ensures the operation is performed securely within the allowed directory, avoiding access to unauthorized paths.
  class RenameFileTool < BuiltInFunction
    name "rename_or_move_file"

    description "Rename a file or directory, or move it to another sub-folder, but you may not move it outside this directory." \
                "like the `mv` command but restricted to the current folder."

    param "source_path", type: Param::Type::Str, required: true,
      description: "The current path of the file or directory to be renamed."
    param "target_path", type: Param::Type::Str, required: true,
      description: "The new name / path for the file or directory."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        current_path = args["source_path"]?.try(&.as_s?) || return error_response("The required `source_path` was not specified")
        new_name = args["target_path"]?.try(&.as_s?) || return error_response("The required `target_path` was not specified")

        resolved_current_path = resolve_path(current_path)
        resolved_new_path = resolve_path(File.join(File.dirname(resolved_current_path), new_name))

        if resolved_current_path.starts_with?(DELETED_FILES_RESOLVED_PATH)
          return error_response("Cannot rename files in the `#{DELETED_FILES_PATH}` directory.")
        end
        if resolved_new_path.starts_with?(DELETED_FILES_RESOLVED_PATH)
          return error_response("Cannot move files into the `#{DELETED_FILES_PATH}` directory.")
        end

        return error_response("Access to the specified path" \
                              " '#{current_path}' is not allowed.") unless within_current_directory?(resolved_current_path)
        return error_response("The specified file or directory '#{current_path}' does not exist.") unless valid_path?(resolved_current_path)
        return error_response("A file or directory with the" \
                              " new name '#{new_name}' already exists.") if File.exists?(resolved_new_path)

        begin
          File.rename(resolved_current_path, resolved_new_path)
          success_response(current_path, new_name)
        rescue e
          error_response("An error occurred while renaming the file: #{e.message}")
        end
      end

      private def success_response(old_name, new_name)
        {message: "File '#{old_name}' renamed to '#{new_name}' successfully."}.to_json
      end

      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
