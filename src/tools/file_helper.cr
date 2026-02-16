require "base64"
require "mime"

module Tools
  class FileLoadingError < Exception; end

  module FileHelper
    DELETED_FILES_PATH    = ".deleted_files/"
    MAX_FIND_FILE_MATCHES = 1000

    def resolve_path(path)
      File.expand_path(path)
    end

    private def file_exists?(path)
      File.exists?(path)
    end

    def path_in_deleted_files_folder?(path : String)
      path.starts_with?(DELETED_FILES_PATH) ||
        path.includes?("/#{DELETED_FILES_PATH}")
    end

    def within_current_directory?(requested_path)
      requested_path.starts_with?(Dir.current)
    end

    def valid_file?(resolved_path)
      File.exists?(resolved_path) && File.file?(resolved_path)
    end

    def find_files(glob_pattern : String, max = MAX_FIND_FILE_MATCHES)
      matches = [] of String
      Dir.glob(glob_pattern) do |path|
        matches << path
        break if matches.size >= max
      end
      matches
    end

    def text_file?(resolved_path)
      File.open(resolved_path, "r") do |file|
        buffer = uninitialized UInt8[1024]
        bytes_read = file.read_utf8(buffer.to_slice)
        String.new(buffer.to_slice[0, bytes_read], "UTF-8").valid_encoding?
      end
    rescue
      false
    end

    def valid_directory?(requested_path)
      Dir.exists?(requested_path)
    end

    MAX_FILESIZE = 32*1024

    # Returns the base64-encoded content of the file regardless of type; assumes path is allowed; raises
    # errors if unable to open file.
    def load_file_as_data_url(resolved_path) : String
      if File.size(resolved_path) > MAX_FILESIZE
        raise FileLoadingError.new("The file '#{resolved_path}' is too big; max allowed is #{MAX_FILESIZE}B")
      end
      content = File.read(resolved_path)
      encoded = Base64.strict_encode(content)
      content_type = MIME.from_filename(resolved_path)
      "data:#{content_type};base64,#{encoded}"
    end
  end
end
