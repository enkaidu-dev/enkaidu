require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `WriteTextFileTool` class defines a tool for a creating or overwriting a file, ensuring the operation is performed within
  # the current directory.
  class WriteTextFileTool < BuiltInFunction
    name "write_text_file"

    description "Write a text file with the given content, ensuring path to file is within current directory.  " \
                "Create entire path to the file if needed. DOES NOT overwrite existing file unless requested."

    param "file_path", type: Param::Type::Str, description: "The relative path where the text file will be created.", required: true
    param "overwrite", type: Param::Type::Bool, description: "Set to true to overwrite existing file; default is false.", required: false
    param "content", type: Param::Type::Str, description: "The content to write into the text file.", required: true

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"].as_s? || return error_response("The required file_path was not specified")
        content = args["content"].as_s? || return error_response("The required content was not specified")
        overwrite = args["overwrite"]?.try(&.as_bool?) || false

        resolved_path = resolve_path(file_path)
        file_exists = file_exists?(resolved_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The file '#{file_path}' already exists.") if !overwrite && file_exists

        begin
          # Ensure directory-sub-tree for file exists
          parent = Path.new(resolved_path).parent
          Dir.mkdir_p(parent) unless Dir.exists?(parent)
          # Create file
          File.write(resolved_path, content)
          success_response(file_path, file_exists)
        rescue ex
          error_response("An error occurred while creating the file: #{ex.message}")
        end
      end

      private def success_response(file_path, overwritten)
        {message: "File '#{file_path}' #{overwritten ? "over-written" : "created"} successfully."}.to_json
      end

      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
