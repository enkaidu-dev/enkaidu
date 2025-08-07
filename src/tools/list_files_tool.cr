require "json"

require "./tools"
require "./file_helper"

class ListFilesTool < LLM::Function
  include FileHelper

  name "list_files"

  # Provide a description for the tool
  description "Lists all files and directories in a specified folder (or the current folder if no path is provided), separating them into categories. Ensures the path stays within the current directory."

  # Define the acceptable parameter using the `param` method
  param "folder", description: "The relative path to the folder to list. Defaults to the current directory if not provided."

  # Define the method that executes the tool's functionality
  def execute(args : JSON::Any) : String
    path = if args.as_s?
             args.as_s
           elsif args["folder"]?
             args["folder"].as_s
           else
             "."
           end

    requested_path = resolve_path(path)

    return error_response("Access to the specified path '#{path}' is not allowed.") unless within_current_directory?(requested_path)
    return error_response("The specified path '#{path}' does not exist or is not a directory.") unless valid_directory?(requested_path)

    entries = list_entries(requested_path)
    files, directories = separate_files_and_directories(entries, requested_path)

    success_response(path, files, directories)
  end

  # List all entries in the specified directory
  private def list_entries(requested_path)
    Dir.entries(requested_path)
  end

  # Separate entries into files and directories
  private def separate_files_and_directories(entries, requested_path)
    files = entries.reject { |entry| File.directory?(File.join(requested_path, entry)) }
    directories = entries.select do |entry|
      File.directory?(File.join(requested_path, entry)) && entry != "." && entry != ".."
    end
    [files, directories]
  end

  # Create a success response as a JSON string
  private def success_response(path, files, directories)
    {
      path:        path,
      files:       files,
      directories: directories,
    }.to_json
  end

  # Create an error response as a JSON string
  private def error_response(message)
    {error: message}.to_json
  end
end
