require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `ReplaceTextInTextFileTool` class defines a tool for replacing specified
  # text in text-based files. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class ReplaceTextInTextFileTool < BuiltInFunction
    name "replace_text_in_text_file"

    description "Searches for the specified text in a text-based file and replaces it with alternative text. " +
                "Ensures the file is within the current directory and is a text file."

    param "file_path", type: Param::Type::Str,
      description: "The relative path to the file where you want to perform the replacement.", required: true
    param "search", type: Param::Type::Str,
      description: "The text to search for in the file.", required: true
    param "replace_with", type: Param::Type::Str,
      description: "The text to use to replace the text we searched for in the file.", required: true

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"]?.try &.as_s? ||
                    return error_response("The required file_path was not specified")
        search_text = args["search"]?.try &.as_s? ||
                      return error_response("The required search_text was not specified")
        replacement_text = args["replace_with"]?.try &.as_s? ||
                           return error_response("The required replacement_text was not specified")

        resolved_path = resolve_path(file_path)

        return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)

        begin
          changes = 0
          content = File.read(resolved_path)
          new_content = content.gsub(search_text) do
            changes += 1 # Count changes so we can detect if nothing changed
            replacement_text
          end
          raise RuntimeError.new("Unable to find search text in the file") if changes.zero?
          # Changes made
          File.write(resolved_path, new_content)
          success_response(file_path, new_content)
        rescue e
          error_response("An error occurred while modifying the file: #{e.message}")
        end
      end

      private def error_response(message)
        {"error" => message}.to_json
      end

      private def success_response(file_path, content)
        {file_path: file_path, new_content: content}.to_json
      end
    end
  end
end
