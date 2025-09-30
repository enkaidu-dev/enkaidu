require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `CreateTextFileTool` class defines a tool for a new file, ensuring the operation is performed within
  # the current directory.
  class CreateTextFileTool < BuiltInFunction
    name "create_text_file"

    description "Creates a text file at the specified path with the given content. " \
                "Ensures the file is created within the current directory and does not overwrite existing files."

    param "file_path", type: Param::Type::Str, description: "The relative path where the text file will be created.", required: true
    param "content", type: Param::Type::Str, description: "The content to write into the text file.", required: true

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"].as_s? || return error_response("The required file_path was not specified")
        content = args["content"].as_s? || return error_response("The required content was not specified")

        resolved_path = resolve_path(file_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The file '#{file_path}' already exists.") if file_exists?(resolved_path)

        begin
          File.write(resolved_path, content)
          success_response(file_path)
        rescue ex
          error_response("An error occurred while creating the file: #{ex.message}")
        end
      end

      private def success_response(file_path)
        {message: "File '#{file_path}' created successfully."}.to_json
      end

      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
