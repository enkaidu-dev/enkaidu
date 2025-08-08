require "json"

require "../tools"
require "./file_helper"

class RenameFileTool < LLM::LocalFunction
  name "rename_file"

  description "Renames a specified file to a new name within the current directory."

  param "current_path", type: LLM::ParamType::Str, description: "The current path of the file to be renamed.", required: true
  param "new_name", type: LLM::ParamType::Str, description: "The new name for the file.", required: true

  runner Runner

  class Runner < LLM::Function::Runner
    include FileHelper

    def execute(f : LLM::Function, args : JSON::Any) : String
      current_path = args["current_path"].as_s? || return error_response("The required current_path was not specified")
      new_name = args["new_name"].as_s? || return error_response("The required new_name was not specified")

      resolved_current_path = resolve_path(current_path)
      resolved_new_path = resolve_path(File.join(File.dirname(resolved_current_path), new_name))

      return error_response("Access to the specified path '#{current_path}' is not allowed.") unless within_current_directory?(resolved_current_path)
      return error_response("The specified file '#{current_path}' does not exist.") unless valid_file?(resolved_current_path)
      return error_response("A file or directory with the new name '#{new_name}' already exists.") if File.exists?(resolved_new_path)

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
