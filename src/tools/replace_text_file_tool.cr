require "json"

require "../tools"
require "./file_helper"

class ReplaceTextInTextFileTool < LLM::Function
  include FileHelper
  name "replace_text_in_text_file"

  description "Replaces specified text in a text-based file with new text. Ensures the file is within the current directory and is a text file."

  param "file_path", type: LLM::ParamType::Str, description: "The relative path to the file where you want to perform the replacement.", required: true
  param "search_text", type: LLM::ParamType::Str, description: "The text to search for in the file.", required: true
  param "replacement_text", type: LLM::ParamType::Str, description: "The text to replace the search_text with in the file.", required: true

  def execute(args : JSON::Any) : String
    file_path = args["file_path"].as_s? || return error_response("The required file_path was not specified")
    search_text = args["search_text"].as_s? || return error_response("The required search_text was not specified")
    replacement_text = args["replacement_text"].as_s? || return error_response("The required replacement_text was not specified")

    resolved_path = resolve_path(file_path)

    return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
    return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)

    begin
      content = File.read(resolved_path)
      new_content = content.gsub(search_text, replacement_text)
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
