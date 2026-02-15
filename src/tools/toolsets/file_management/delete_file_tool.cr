require "json"
require "../../built_in_function"
require "../../file_helper"
require "time"

module Tools::FileManagement
  # The `DeleteFileTool` class defines a tool to delete a file by moving it to a
  # ".deleted_files/" folder, where it preserves the files location path and
  # prepends a timestamp prepended to the filename.
  class DeleteFileTool < BuiltInFunction
    name "delete_file"

    description "Deletes a specified file by moving it to a '#{FileHelper::DELETED_FILES_PATH}' folder with a ms-resolution timestamp " \
                "prepended to the filename. This allows for file recovery if deletion was accidental. The directory " \
                "structure is preserved in the deleted_files folder."

    param "file_path", type: Param::Type::Str,
      description: "The path of the file to be deleted.", required: true

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"].as_s? || return error_response("The required file_path was not specified")

        resolved_file_path = resolve_path(file_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_file_path)
        return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_file_path)

        # Prevent deletion of files from the DELETED_FILES_PATH folder
        deleted_dir = resolve_path(DELETED_FILES_PATH)
        if resolved_file_path.starts_with?(deleted_dir)
          return error_response("Cannot delete files from the `#{DELETED_FILES_PATH}` folder.")
        end

        # Create the deleted_files directory if it doesn't exist
        unless Dir.exists?(deleted_dir)
          begin
            Dir.mkdir(deleted_dir)
          rescue e
            return error_response("Failed to create deleted files directory: #{e.message}")
          end
        end

        # Generate timestamp and new filename
        timestamp = Time.local.to_s("%Y%m%d_%H%M%S_%L")
        filename = File.basename(resolved_file_path)

        # Preserve directory structure in the deleted_files folder
        dir_structure = File.dirname(file_path)
        new_filename = "#{timestamp}_#{filename}"
        target_path = if dir_structure == "."
                        # If file is in root directory, just use timestamped filename
                        File.join(deleted_dir, new_filename)
                      else
                        # Create the directory structure in deleted_files folder
                        full_deleted_path = File.join(deleted_dir, dir_structure)
                        Dir.mkdir_p(full_deleted_path)
                        # Add timestamp to the filename while preserving directory structure
                        File.join(full_deleted_path, new_filename)
                      end

        # Move the file to the deleted_files directory
        begin
          File.rename(resolved_file_path, target_path)
          success_response(file_path, target_path)
        rescue e
          error_response("An error occurred while deleting the file: #{e.message}")
        end
      end

      private def success_response(old_path, new_path)
        {message: "File deleted successfully, by renaming '#{old_path}' to '#{new_path}'."}.to_json
      end

      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
