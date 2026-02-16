require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::FileManagement
  # The `SearchFilesTool` class defines a tool for searching for text
  # in all files found using a glob pattern. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class SearchFilesTool < BuiltInFunction
    name "search_files"

    description "Searches files for lines for lines containing a match to the given search pattern and returns matching lines with line numbers."

    param "files", required: true,
      description: "A single file path, or a glob pattern expression with which to find matching files."
    param "pattern", type: Param::Type::Str,
      description: "The text or pattern to search for in each file.", required: true
    param "search_regex", type: Param::Type::Bool, required: false,
      description: "Optional, set to true to indicate `search_pattern` is a regular expression (default is false.)"
    param "max_files", type: Param::Type::Num,
      description: "Optional, maxmimum number of files to search within (default is #{FileHelper::MAX_FIND_FILE_MATCHES})"

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      def execute(args : JSON::Any) : String
        files_pattern = args["files"]?.try(&.as_s?) || "*"
        max_files = args["max_files"]?.try(&.as_i?) || MAX_FIND_FILE_MATCHES

        unless within_current_directory?(resolve_path(files_pattern))
          return error_response("Looking outside current directory not allowed.")
        end

        if files_pattern.includes?("../") || files_pattern.includes?("/..")
          return error_response("Reverse path navigation (via `..`) not allowed.")
        end

        search_pattern = args["pattern"]?.try &.as_s? ||
                         return error_response("The required search pattern was not specified")

        return error_response("The required search pattern was empty") if search_pattern.strip.empty?

        regex = args["search_regex"]?.try &.as_bool? || false

        begin
          results = [] of NamedTuple(file: String, matches: Array(NamedTuple(line: String, num: Int32)))
          pattern = regex ? Regex.new(search_pattern) : search_pattern
          found = [] of NamedTuple(line: String, num: Int32)
          find_files(files_pattern, max_files) do |file|
            search_file(file, pattern) do |match|
              found << match
            end
            unless found.empty?
              results << {file: file, matches: found}
              found = [] of NamedTuple(line: String, num: Int32)
            end
          end
          success_response(results)
        rescue e
          error_response("An error occurred while modifying the file: #{e.message}")
        end
      end

      private def search_file(file_path : String, pattern : String | Regex, &)
        count = 0
        File.open(file_path, "r") do |io|
          io.each_line(chomp: true) do |line|
            count += 1
            found = case pattern
                    when Regex  then line.matches?(pattern)
                    when String then line.includes?(pattern)
                    end
            yield({line: line, num: count}) if found
          end
        end
      end

      private def error_response(message)
        {"error" => message}.to_json
      end

      private def success_response(found)
        found.to_json
      end
    end
  end
end
