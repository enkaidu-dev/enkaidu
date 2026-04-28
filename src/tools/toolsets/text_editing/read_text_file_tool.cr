require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `ReadTextFileTool` class defines a tool for reading all the text
  # from a file. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class ReadTextFileTool < BuiltInFunction
    name "read_text_file"

    # Provide a description for the tool
    description "Read the contents of a text file within the current directory. " \
                "Read the entire file or a specific range of lines."

    # Define the acceptable parameter using the `param` method
    param "file_path", type: Param::Type::Str, required: true,
      description: "The path to the text file to read."
    param "include_line_numbers", type: Param::Type::Bool, required: false,
      description: "Optional. Set to true to include line numbers, like `cat -n`. Defaults to false."
    param "line_range", type: Param::Type::Arr, required: false,
      description: "Optional. An array of two integers specifying the start and end line numbers to view." \
                   "Line numbers are 1-indexed, and -1 for the end line means read to the end of the file." \
                   "Defaults to [1, -1] for entire file."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"].as_s? || return error_response("The required `file_path` was not specified")
        line_numbers = args["include_line_numbers"]?.try &.as_bool? || false
        line_range = if range = args["line_range"]?
                       if (arr = range.as_a?) && arr.size == 2 && (line_start = arr[0]?.try(&.as_i?)) && (line_end = arr[1]?.try(&.as_i?))
                         [line_start, line_end]
                       else
                         return error_response("The `line_range` must be an array with two integers.")
                       end
                     else
                       [1, -1] # entire file
                     end

        resolved_path = resolve_path(file_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)
        return error_response("The specified file '#{file_path}' is not a text-based file.") unless text_file?(resolved_path)

        begin
          content = read_text_file(resolved_path, line_numbers, line_range)
          success_response(file_path, content)
        rescue e
          error_response("An error occurred while reading the file: #{e.message}")
        end
      end

      private def read_text_file(resolved_path, line_numbers : Bool, line_range)
        if !line_numbers && line_range == [1, -1]
          # whole file, no line numbers.
          File.read(resolved_path)
        else
          # line numbers and/or partial file
          String.build do |io|
            start_line = line_range.first
            end_line = line_range.last
            line_no = 0
            File.each_line(resolved_path, chomp: false) do |line|
              line_no += 1
              if line_no >= start_line && (end_line.negative? || line_no <= end_line)
                io.printf("%6d\t", line_no) if line_numbers
                io << line # un-chomped line includes EOL
              end
            end
          end
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
end
