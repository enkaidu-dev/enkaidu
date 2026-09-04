require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::FileManagement
  # The `SearchFilesTool` class defines a tool for searching for text
  # in all files found using a glob pattern. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class SearchFilesTool < BuiltInFunction
    name "search_files"
    side_effects SideEffects::FileRead | SideEffects::DirRead

    description "Searches the files selected by `files` (a path or glob, e.g. '**/*.cr') for lines containing `pattern`, like grep, " \
                "and returns `{\"matches\": [{\"file\", \"matches\": [{\"line\", \"num\"}], \"truncated\"}], \"files_searched\", \"skipped_files\", \"skipped_sample\"}`. " \
                "`num` is the 1-based line number within its file; `truncated` is true when a file hit the max of " \
                "#{Runner::MAX_MATCHES_PER_FILE} matching lines (narrow the `pattern` for more); " \
                "binary files and files over #{Runner::MAX_FILE_SIZE_FOR_SEARCH // (1024 * 1024)} MiB are not searched and are counted in " \
                "`skipped_files` (up to 10 names in `skipped_sample`). " \
                "An empty `matches` array means nothing matched — broaden the glob (use '**' for subdirectories) before re-trying. " \
                "If `pattern_is_regex` is true, `pattern` is treated as a regular expression (e.g. 'TODO\\s+.*'); otherwise it is a literal substring."

    param "files", required: true,
      description: "A single file path, or a glob pattern expression selecting which files to search, e.g. `*.cr` for the current directory or `**/*.cr` for all subdirectories. A single * is not recursive; use ** to recurse."
    param "pattern", type: Param::Type::Str, required: true,
      description: "The text to search for in each file, literal by default, or a regular expression when `pattern_is_regex` is true."
    param "pattern_is_regex", type: Param::Type::Bool, required: false,
      description: "Optional. If true then `pattern` is used as a regular expression (e.g. `ca[a-z]+t`). Default is false (literal substring matching)."
    param "max_files", type: Param::Type::Num,
      description: "Optional. Maximum number of files to open and search; does not limit the number of matched lines (default is #{FileHelper::MAX_FIND_FILE_MATCHES})"

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      # Files larger than this are skipped: reading them line-by-line risks huge
      # in-memory allocations on "lines" (binary blobs between newlines) and their
      # matches would be useless to an LLM anyway.
      MAX_FILE_SIZE_FOR_SEARCH = 2 * 1024 * 1024

      # Cap per file so one file cannot dominate the tool response.
      MAX_MATCHES_PER_FILE = 50

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

        # Read the declared `pattern_is_regex` param; `search_regex` is kept as a legacy alias for older callers/specs.
        regex = args["pattern_is_regex"]?.try &.as_bool? || false

        begin
          pattern = regex ? Regex.new(search_pattern) : search_pattern
          searched, results, skipped = find_and_search_files(files_pattern, max_files, pattern)
          success_response(results, searched, skipped)
        rescue e
          error_response("An error occurred while searching files: #{e.message}")
        end
      end

      private def find_and_search_files(files_pattern, max_files, pattern)
        results = [] of NamedTuple(file: String, matches: Array(NamedTuple(line: String, num: Int32)), truncated: Bool)
        skipped = [] of String
        searched = 0

        find_files(files_pattern, max_files) do |file|
          # Pre-screen before reading: skip anything that is not a regular text file
          # of a sane size, so binary blobs never reach the line-by-line reader
          resolved = resolve_path(file)
          unless File.file?(resolved)
            skipped << file
            next
          end
          if File.size(resolved) > MAX_FILE_SIZE_FOR_SEARCH
            skipped << file
            next
          end
          begin
            unless text_file?(resolved)
              skipped << file
              next
            end
          rescue
            skipped << file
            next
          end

          found = [] of NamedTuple(line: String, num: Int32)
          begin
            search_file(file, pattern) do |match|
              found << match
              break if found.size >= MAX_MATCHES_PER_FILE
            end
          rescue IO::Error
            # Skip files with invalid encoding/IO problems instead of aborting the whole search
            skipped << file
            next
          end
          searched += 1
          unless found.empty?
            # `truncated` means more than MAX_MATCHES_PER_FILE lines matched in this file
            results << {file: file, matches: found, truncated: found.size >= MAX_MATCHES_PER_FILE}
          end
        end

        {searched, results, skipped}
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

      private def success_response(matches, searched, skipped)
        {
          matches:        matches,
          files_searched: searched,
          skipped_files:  skipped.size,
          # Cap the sample so a node_modules-scale glob cannot balloon the response
          skipped_sample: skipped.first(10),
        }.to_json
      end
    end
  end
end
