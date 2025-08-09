require "json"

require "../tools"
require "./file_helper"

# The `ReadTextFileTool` class defines a tool for reading all the text
# from a file. It ensures the operation is performed securely within the
# allowed directory, avoiding access to unauthorized paths.
class ReadTextFileTool < LLM::LocalFunction
  name "read_text_file"

  # Provide a description for the tool
  description "Reads the content of a specified text-based file in the current directory. " \
              "Supports plain text, code files, markdown, and other text-based formats. " \
              "Ensures the file is within the current directory and is not a binary file."

  # Define the acceptable parameter using the `param` method
  param "file_path", type: LLM::ParamType::Str, description: "The relative path to the text file to read.", required: true

  runner Runner

  # The Runner class executes the function
  class Runner < LLM::Function::Runner
    include FileHelper

    def execute(f : LLM::Function, args : JSON::Any) : String
      file_path = args["file_path"].as_s? || return error_response("The required file_path was not specified")

      resolved_path = resolve_path(file_path)

      return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
      return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)
      return error_response("The specified file '#{file_path}' is not a text-based file.") unless text_file?(resolved_path)

      begin
        content = File.read(resolved_path)
        success_response(file_path, content)
      rescue e
        error_response("An error occurred while reading the file: #{e.message}")
      end
    end

    # Create a success response as a JSON string
    def success_response(file_path, content)
      {
        file_path: file_path,
        content:   content,
      }.to_json
    end

    # Create an error response as a JSON string
    private def error_response(message)
      {error: message}.to_json
    end
  end
end
