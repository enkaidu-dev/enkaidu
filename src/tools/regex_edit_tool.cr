require "json"

require "../tools"
require "./file_helper"

# The `RegexTextEditTool` class defines a tool for finding patterns using regex
# in text-based files and replacing them with new text.
class RegexTextEditTool < LLM::LocalFunction
  name "regex_text_edit_tool"

  description "Finds patterns using a regex in a text-based file and replaces them with new text."

  param "file_path", type: LLM::ParamType::Str,
    description: "The relative path to the file where you want to perform the regex replacement.", required: true
  param "pattern", type: LLM::ParamType::Str,
    description: "The regex pattern to search for in the file.", required: true
  param "replacement", type: LLM::ParamType::Str,
    description: "The text to replace the pattern with in the file.", required: true

  runner Runner

  # The Runner class executes the function
  class Runner < LLM::Function::Runner
    include FileHelper

    def execute(args : JSON::Any) : String
      file_path = args["file_path"]?.try &.as_s? || return error_response("The required file_path was not specified")
      pattern = args["pattern"]?.try &.as_s? || return error_response("The required pattern was not specified")
      replacement = args["replacement"]?.try &.as_s? || return error_response("The required replacement was not specified")

      resolved_path = resolve_path(file_path)

      return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
      return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)

      begin
        content = File.read(resolved_path)
        new_content = content.gsub(Regex.new(pattern, Regex::Options::MULTILINE), replacement)
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
