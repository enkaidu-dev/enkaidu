require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `ReplaceTextInTextFileTool` class defines a tool for replacing specified
  # text in text-based files. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class ReplaceTextInTextFileTool < BuiltInFunction
    name "str_replace_in_text_file"

    description "Replaces a specified string in a text file within the current directory with a new string." \
                "This is used for making precise edits."

    param "file_path", type: Param::Type::Str,
      description: "The relative path to the text file to modify.", required: true
    param "old_str", type: Param::Type::Str,
      description: "The text to replace (must match exactly, including whitespace and indentation)", required: true
    param "new_str", type: Param::Type::Str,
      description: "The new text to insert in place of the old text.", required: true
    param "multiple", type: Param::Type::Bool, required: false,
      description: "If true, tries to replaces multiple occurrences of the old string. Default is false, replacing only the first occurence."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"]?.try &.as_s? ||
                    return error_response("The required `file_path` was not specified")
        search_text = args["old_str"]?.try &.as_s? ||
                      return error_response("The required `old_str` was not specified")
        replacement_text = args["new_str"]?.try &.as_s? ||
                           return error_response("The required `new_str` was not specified")
        multiple = args["multiple"]?.try &.as_bool? || false

        resolved_path = resolve_path(file_path)

        return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist or is not a file.") unless valid_file?(resolved_path)

        begin
          changes = 0
          content = File.read(resolved_path)
          if multiple
            new_content = content.gsub(search_text) do
              changes += 1 # Count changes so we can detect if nothing changed
              replacement_text
            end
          else
            # Replace first occurrence only
            new_content = content.sub(search_text) do
              changes += 1 # Count changes so we can detect if nothing changed
              replacement_text
            end
          end
          raise RuntimeError.new("Unable to find old string in the file. Nothing to replace.") if changes.zero?
          # Changes made
          File.write(resolved_path, new_content)
          success_response(file_path, new_content, changes)
        rescue e
          error_response("An error occurred while modifying the file: #{e.message}")
        end
      end

      private def error_response(message)
        {"error" => message}.to_json
      end

      private def success_response(file_path, content, changes : Int32)
        {file_path: file_path, new_content: content, replacements: changes}.to_json
      end
    end
  end
end
