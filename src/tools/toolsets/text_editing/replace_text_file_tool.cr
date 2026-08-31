require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::TextEditing
  # The `ReplaceTextInTextFileTool` class defines a tool for replacing specified
  # text in text-based files. It ensures the operation is performed securely within the
  # allowed directory, avoiding access to unauthorized paths.
  class ReplaceTextInTextFileTool < BuiltInFunction
    name "str_replace_in_text_file"
    side_effects SideEffects::FileRead | SideEffects::FileWrite

    description "Replaces a specified string in a text file within the current directory with a new string." \
                "This is used for making precise edits."

    param "file_path", type: Param::Type::Str, required: true,
      description: "The relative path to the text file to modify."
    param "old_str", type: Param::Type::Str, required: true,
      description: "The exact text to find and replace. Must match byte-for-byte. " \
                   "Include enough surrounding lines to make the match unique. " \
                   "Tip: if a previous read_text_file call included line numbers, do not include them here."
    param "new_str", type: Param::Type::Str, required: true,
      description: "The new text to insert in place of the old text."
    param "multiple", type: Param::Type::Bool, required: false,
      description: "Optional. If true, tries to replaces multiple occurrences of the old string. Default is false, replacing only the first occurence."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      CONTEXT_LINES = 2

      # Main entry point: performs the string replacement and returns structured results.
      #
      # - Extracts and validates required parameters (file_path, old_str, new_str, multiple)
      # - Resolves the file path and verifies it is within the allowed directory
      # - Rejects paths that point to the deleted-files folder
      # - Reads the file content
      # - Finds all match positions of the search text in the content
      # - Raises an error if no matches are found
      # - Applies the replacement to produce new content
      # - Builds change hunks (before/after snippets with context) for the response
      # - Writes the new content to disk
      # - Returns a JSON-encoded success response with the file path, replacement count,
      #   and an array of change hunks
      def execute(args : JSON::Any) : String
        file_path = args["file_path"]?.try &.as_s? ||
                    return error_response("The required `file_path` was not specified")
        search_text = args["old_str"]?.try &.as_s? ||
                      return error_response("The required `old_str` was not specified")
        replacement_text = args["new_str"]?.try &.as_s? ||
                           return error_response("The required `new_str` was not specified")
        multiple = args["multiple"]?.try &.as_bool? || false

        resolved_path = resolve_path(file_path)

        return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist or is not a file.") unless valid_file?(resolved_path)
        return error_response("Cannot edit files in the `#{DELETED_FILES_PATH}` folder.") if path_in_deleted_files_folder?(resolved_path)

        begin
          content = File.read(resolved_path)
          match_positions = find_match_positions(content, search_text, multiple)
          raise RuntimeError.new("Unable to find old string in the file. Nothing to replace.") if match_positions.empty?

          new_content = apply_replacement(content, search_text, replacement_text, multiple)
          changes = build_change_hunks(content, search_text, replacement_text, match_positions, multiple)
          File.write(resolved_path, new_content)
          success_response(file_path, changes, match_positions.size)
        rescue e
          error_response("An error occurred while modifying the file: #{e.message}")
        end
      end

      # Finds all byte offset positions of `search_text` within `content`.
      #
      # - Scans `content` from the start to find the first occurrence of `search_text`
      # - Records the byte offset of each match
      # - If `multiple` is true, continues scanning after each match to find all occurrences
      # - If `multiple` is false, stops after the first match
      # - Returns an empty array if no match is found
      private def find_match_positions(content : String, search_text : String, multiple : Bool) : Array(Int32)
        positions = [] of Int32
        start = 0
        loop do
          idx = content.index(search_text, start)
          break if idx.nil?
          positions << idx
          break unless multiple
          start = idx + search_text.size
        end
        positions
      end

      # Produces the new file content by performing the actual string replacement.
      #
      # - If `multiple` is true, replaces all occurrences of `search_text` with `replacement_text`
      # - If `multiple` is false, replaces only the first occurrence
      # - Returns the fully updated string ready to be written to the file
      private def apply_replacement(content : String, search_text : String, replacement_text : String, multiple : Bool) : String
        if multiple
          content.gsub(search_text, replacement_text)
        else
          content.sub(search_text, replacement_text)
        end
      end

      # Builds the array of change hunks to include in the response, showing only
      # the regions of the file that were affected (plus surrounding context).
      #
      # - Converts each match's byte offset into a start/end line range
      # - Expands each range by CONTEXT_LINES above and below to include surrounding context
      # - Clamps expanded ranges to valid line numbers (1 through total lines in the file)
      # - Merges overlapping or adjacent expanded ranges into unified hunks
      # - For each merged range, extracts the original text as `before` and applies the
      #   replacement within the snippet to produce `after`
      # - Returns an array of hash entries, each with: start_line, end_line, before, after
      private def build_change_hunks(content : String, search_text : String, replacement_text : String,
                                     match_positions : Array(Int32), multiple : Bool)
        line_ranges = match_positions.map { |pos| match_line_range(content, pos, search_text.size) }
        expanded = line_ranges.map do |start, stop|
          {start - CONTEXT_LINES, stop + CONTEXT_LINES}
        end
        total_lines = content.count('\n') + 1
        expanded = expanded.map do |start, stop|
          {Math.max(1, start), Math.min(total_lines, stop)}
        end
        merged = merge_ranges(expanded)

        merged.map do |start_line, end_line|
          before = extract_lines(content, start_line, end_line)
          after = if multiple
                    before.gsub(search_text, replacement_text)
                  else
                    before.sub(search_text, replacement_text)
                  end
          {
            "start_line" => start_line,
            "end_line"   => end_line,
            "before"     => before,
            "after"      => after,
          }
        end
      end

      # Converts a byte offset into a 1-based line range (start_line, end_line)
      # for a match beginning at `byte_offset` with `match_size` bytes.
      #
      # - Counts the number of newline characters before `byte_offset` to determine the
      #   1-based line number where the match starts
      # - Counts the number of newline characters up to the end of the match
      #   (`byte_offset + match_size`) to determine the 1-based line number where it ends
      # - Returns a Tuple of (start_line, end_line); both will be equal for single-line matches
      private def match_line_range(content : String, byte_offset : Int32, match_size : Int32) : Tuple(Int32, Int32)
        start_line = content[0...byte_offset].count('\n') + 1
        end_line = content[0...(byte_offset + match_size)].count('\n') + 1
        {start_line, end_line}
      end

      # Merges a list of (start, end) line ranges into a minimal set of non-overlapping
      # ranges, combining any that overlap or are adjacent.
      #
      # - Returns an empty array if no ranges are provided
      # - Sorts the input ranges by their start line
      # - Iterates from the second range forward, comparing each to the last merged range
      # - If the current range starts at or before (last merged end + 1), it overlaps or is
      #   adjacent, so the last merged range's end is extended to cover the current range
      # - Otherwise, the current range is appended as a new merged range
      # - Returns the final array of merged ranges
      private def merge_ranges(ranges : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
        return [] of {Int32, Int32} if ranges.empty?
        sorted = ranges.sort { |a, b| a[0] <=> b[0] }
        merged = [sorted[0]]
        (1...sorted.size).each do |i|
          cur_start = sorted[i][0]
          cur_end = sorted[i][1]
          last_start = merged.last[0]
          last_end = merged.last[1]
          if cur_start <= last_end + 1
            merged[-1] = {last_start, Math.max(last_end, cur_end)}
          else
            merged << {cur_start, cur_end}
          end
        end
        merged
      end

      # Extracts the text of a contiguous range of lines from `content`.
      #
      # - Splits `content` on newline characters into an array of individual lines
      # - Slices the array from `start_line - 1` for the number of lines in the range
      # - Joins the sliced lines back together with newlines
      # - Returns the resulting multi-line string (no trailing newline)
      # - Note: line numbers are 1-based
      private def extract_lines(content : String, start_line : Int32, end_line : Int32) : String
        content.split("\n")[start_line - 1, end_line - start_line + 1].join("\n")
      end

      private def error_response(message)
        {"error" => message}.to_json
      end

      private def success_response(file_path, changes, replacements : Int32)
        {file_path: file_path, replacements: replacements, changes: changes}.to_json
      end
    end
  end
end
