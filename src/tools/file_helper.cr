require "base64"
require "mime"

module Tools
  class FileLoadingError < Exception; end

  module FileHelper
    DELETED_FILES_PATH          = ".deleted_files/"
    DELETED_FILES_RESOLVED_PATH = File.expand_path(DELETED_FILES_PATH)
    MAX_FIND_FILE_MATCHES       = 1000

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
      File.file?(resolved_path) # also checks for existence
    end

    def valid_path?(resolved_path)
      File.exists?(resolved_path)
    end

    def find_files(glob_pattern : String, max = MAX_FIND_FILE_MATCHES, sort = false)
      matches = [] of String
      find_files(glob_pattern, max) do |path|
        matches << path
      end
      matches.sort! if sort
      matches
    end

    def find_files(glob_pattern : String, max = MAX_FIND_FILE_MATCHES, &)
      count = 0
      Dir.glob(glob_pattern) do |path|
        yield path
        break if (count += 1) >= max
      end
      count
    end

    def text_file?(resolved_path)
      File.open(resolved_path, "r") do |file|
        buffer = uninitialized UInt8[1024]
        bytes_read = file.read(buffer.to_slice)
        slice = buffer.to_slice[0, bytes_read]

        # Back up to skip any incomplete trailing multibyte sequence
        # including the first byte of multibyte sequence
        last = bytes_read - 1
        while last > 0 && (slice[last] & 0xC0) == 0x80
          last -= 1
        end
        # Now slice[0, last] contains only complete characters
        String.new(slice[0, last], "UTF-8").valid_encoding?
      rescue
        false
      end
    end

    def valid_directory?(requested_path)
      Dir.exists?(requested_path)
    end

    MAX_FILESIZE = 32*1024

    # Returns the base64-encoded content (not a data URL) of the file regardless of type; assumes path is allowed; raises
    # errors if unable to open file.
    def load_file_as_base64_data(resolved_path, max_file_size = MAX_FILESIZE) : String
      if File.size(resolved_path) > max_file_size
        raise FileLoadingError.new("The file '#{resolved_path}' is too big; max allowed is #{max_file_size.format}B")
      end
      content = File.read(resolved_path)
      Base64.strict_encode(content)
    end

    # Returns the base64-encoded content of the file regardless of type; assumes path is allowed; raises
    # errors if unable to open file.
    def load_file_as_data_url(resolved_path) : String
      encoded = load_file_as_base64_data(resolved_path)
      content_type = MIME.from_filename(resolved_path)
      "data:#{content_type};base64,#{encoded}"
    end
  end
end
