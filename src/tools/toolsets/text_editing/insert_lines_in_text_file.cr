require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `InsertLinesInTextFileTool` class defines a tool for inserting text at
  # a specific line in a text file. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class InsertLinesInTextFileTool < BuiltInFunction
    name "str_insert_in_text_file"

    description "Insert text at a specific location in a text file within the current directory."

    param "file_path", type: Param::Type::Str,
      description: "The relative path to the text file to modify.", required: true
    param "insert_line", type: Param::Type::Num,
      description: "The line number after which to insert the text (0 for beginning of file, -1 to append at the end)", required: true
    param "insert_text", type: Param::Type::Num,
      description: "The text to insert.", required: true

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"]?.try &.as_s? ||
                    return error_response("The required `file_path` was not specified")
        insert_line = args["insert_line"]?.try &.as_i? ||
                      return error_response("The required `insert_line` was not specified")
        insert_text = args["insert_text"]?.try &.as_s? ||
                      return error_response("The required `insert_text` was not specified")

        resolved_path = resolve_path(file_path)

        return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist or is not a file.") unless valid_file?(resolved_path)

        begin
          new_content = if insert_line.negative?
                          String.build do |io|
                            io << File.read(resolved_path)
                            io << insert_text
                          end
                        else
                          String.build do |io|
                            line_no = 0
                            inserted = false
                            File.each_line(resolved_path, chomp: false) do |line|
                              if insert_line == line_no # 0-based point
                                io << insert_text
                                inserted = true
                              end
                              io << line   # un-chomped line includes EOL
                              line_no += 1 # be careful, useless if inserted == true
                            end
                            # in case line number > last line
                            io << insert_text if !inserted && insert_line == line_no
                          end
                        end
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
