require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `InsertLinesInTextFileTool` class defines a tool for inserting text at
  # a specific line in a text file. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class ReplaceLinesInTextFileTool < BuiltInFunction
    name "str_replace_lines_in_text_file"

    description "Replace a range of lines in a text file within the current directory with given text."

    param "file_path", type: Param::Type::Str,
      description: "The relative path to the text file to modify.", required: true
    param "line_range", type: Param::Type::Arr, required: true,
      description: "An array of two integers specifying the start and end line numbers." \
                   "Line numbers are 1-indexed, and -1 for the end line means read to the end of the file."
    param "new_str", type: Param::Type::Num,
      description: "The new text to insert in place of the replaced lines.", required: true

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"]?.try &.as_s? ||
                    return error_response("The required `file_path` was not specified")
        new_str = args["new_str"]?.try &.as_s? ||
                  return error_response("The required `new_str` was not specified")
        resolved_path = resolve_path(file_path)

        return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist or is not a file.") unless valid_file?(resolved_path)
        return error_response("Cannot edit files in the `#{DELETED_FILES_PATH}` folder.") if path_in_deleted_files_folder?(resolved_path)

        begin
          line_range = parse_line_range(args["line_range"]?)

          if new_content = replace_lines(resolved_path, line_range, new_str)
            File.write(resolved_path, new_content)
            success_response(file_path, "Successfully replaced lines in the range #{line_range} in the text file.")
          else
            error_response("Replacement failed, file hass less lines that #{line_range.first}. File not modified. ")
          end
        rescue e
          error_response(e.message)
        end
      end

      private def parse_line_range(range)
        if range
          if (arr = range.as_a?) && arr.size == 2 && (line_start = arr[0]?.try(&.as_i?)) && (line_end = arr[1]?.try(&.as_i?))
            if line_start >= 0 && (line_end.negative? || line_start <= line_end)
              [line_start, line_end]
            else
              raise Exception.new("The `line_range` is invalid: start line (#{line_start}) > end line (#{line_end})")
            end
          else
            raise Exception.new("The `line_range` must be an array with two integers.")
          end
        else
          raise Exception.new("The required `line_range` was not specified")
        end
      end

      private def replace_lines(resolved_path, line_range, new_str) : String?
        replaced = false
        new_content = String.build do |io|
          line_no = 0
          start_line = line_range.first
          end_line = line_range.last

          File.each_line(resolved_path, chomp: false) do |line|
            line_no += 1
            if line_no < start_line
              io << line
            elsif line_no == start_line && end_line.negative?
              io << new_str
              replaced = true
              break # short-circuit reading loop
            elsif line_no == end_line
              # if we get here, we're at last line to range to replace
              # and we're NOT replacing to end of file
              io << new_str
              # If line has newline, give it back
              io.puts if line.chomp.size < line.size
              replaced = true
            elsif line_no > end_line
              io << line
            end
          end
        end
        replaced ? new_content : nil
      end

      private def error_response(message)
        {"error" => message}.to_json
      end

      private def success_response(file_path, message)
        {file_path: file_path, status: "Success", message: message}.to_json
      end
    end
  end
end
