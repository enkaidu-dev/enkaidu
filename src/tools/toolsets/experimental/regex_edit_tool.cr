require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::Experimental
  # The `RegexTextEditTool` class defines a tool for finding patterns using regex
  # in text-based files and replacing them with new text.
  class RegexTextEditTool < BuiltInFunction
    name "str_regex_replace_in_text_file"

    description "Replaces strings that match a regular expression with a new string in a text file within the current directory."

    param "file_path", type: Param::Type::Str, required: true,
      description: "The relative path to the file where you want to perform the regex replacement."
    param "pattern", type: Param::Type::Str, required: true,
      description: "The regular expression pattern to search for in the file."
    param "new_str", type: Param::Type::Str, required: true,
      description: "The text to replace the pattern with in the file."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"]?.try &.as_s? || return error_response("The required `file_path` was not specified")
        pattern = args["pattern"]?.try &.as_s? || return error_response("The required regex `pattern` was not specified")
        replacement = args["new_str"]?.try &.as_s? || return error_response("The replacement `new_str` was not specified")

        resolved_path = resolve_path(file_path)

        return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)
        return error_response("Cannot edit files in the `#{DELETED_FILES_PATH}` folder.") if path_in_deleted_files_folder?(resolved_path)

        begin
          changes = 0
          content = File.read(resolved_path)
          new_content = content.gsub(Regex.new(pattern, Regex::Options::MULTILINE)) do |_match|
            changes += 1 # Count changes so we can detect if nothing changed
            replacement
          end
          raise RuntimeError.new("Unable to find strings matching the regex pattern in the file. Nothing to replace.") if changes.zero?
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
