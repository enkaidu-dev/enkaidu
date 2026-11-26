module Tools
  # Backwards compatibility for renamed tools.
  # Maps deprecated (old) tool names to their current names.
  module Compatibility
    DEPRECATED_NAMES = {
      "read_text_file"                 => "read_text",
      "write_text_file"                => "write_text",
      "str_replace_in_text_file"       => "replace_text",
      "str_insert_in_text_file"        => "insert_lines",
      "str_replace_lines_in_text_file" => "replace_lines",
      "find_files"                     => "find",
      "search_files"                   => "search",
      "create_directory"               => "mkdir",
      "delete_file"                    => "rm",
      "rename_or_move_file"            => "mv",
      "get_current_datetime"           => "date",
      "http_get_web_page"              => "fetch_html",
      "http_get_web_page_as_markdown"  => "fetch_markdown",
      "read_audio_file"                => "read_audio",
      "create_audio_file"              => "write_audio",
      "read_image_file"                => "read_image",
      "write_image_file"               => "write_image",
    } of String => String

    # Reverse lookup: given a current name, return the old name if one exists
    DEPRECATED_NAMES_REVERSE = DEPRECATED_NAMES.invert

    @@warned = false

    # Resolve an enumerable of tool names, mapping any deprecated names to current ones
    def self.resolve(names : Enumerable(String)) : Array(String)
      names.map { |name| DEPRECATED_NAMES[name]? || name }
    end

    # Resolve a single tool name
    def self.resolve_single(name : String) : String
      DEPRECATED_NAMES[name]? || name
    end

    # Check if any name in the enumerable is a deprecated name
    def self.any_deprecated?(names : Enumerable(String)) : Bool
      names.any? { |name| DEPRECATED_NAMES.has_key?(name) }
    end

    # Check if a single name is deprecated
    def self.deprecated?(name : String) : Bool
      DEPRECATED_NAMES.has_key?(name)
    end

    # Given a current tool name, return the deprecated (old) name if one maps to it
    def self.old_name_for?(new_name : String) : String?
      DEPRECATED_NAMES_REVERSE[new_name]?
    end

    # Whether the deprecation warning has been shown
    def self.warned? : Bool
      @@warned
    end

    # Mark the deprecation warning as shown
    def self.mark_warned!
      @@warned = true
    end

    # Render a markdown table of the name mappings for use in a warning's help
    def self.deprecation_table : String
      String.build do |io|
        io << "| Deprecated | Current |\n"
        io << "|---|---|\n"
        DEPRECATED_NAMES.each do |old, new|
          io << "| `#{old}` | `#{new}` |\n"
        end
      end
    end
  end
end
