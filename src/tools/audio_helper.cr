require "base64"

require "./file_helper"

module Tools
  class AudioLoadingError < Exception; end

  module AudioHelper
    include FileHelper

    # Allowed image content types
    ALLOWED_AUDIO_FORMATS = ["wav", "mp3"]

    # Base64-encoded magic bytes for allowed audio formats
    # without padding so we can do prefix checking.
    ALLOWED_AUDIO_MAGIC_B64 = [
      /^UklGR.+?QVZF/, # wav
      /^SUQz/,         # mp3
    ]

    UNKNOWN_AUDIO_FORMAT = "unknown"
    MAX_AUDIO_FILE_SIZE  = 32*1024*1024

    # Determines the content type based on the magic bytes of the image
    def determine_audio_format(base64_encoded_string : String) : String
      # Check the base64 string for encoded magic bytes
      ALLOWED_AUDIO_MAGIC_B64.each_with_index do |magic, i|
        return ALLOWED_AUDIO_FORMATS[i] if base64_encoded_string.starts_with?(magic)
      end
      UNKNOWN_AUDIO_FORMAT
    end

    def allowed_audio?(base64_encoded_string : String)
      determine_audio_format(base64_encoded_string) != UNKNOWN_AUDIO_FORMAT
    end

    # Returns the base64-encoded data for the contents of an au; assumes path is allowed; raises
    # errors if unable to open file or if content is not an allowed image
    def load_audio_file_as_data(resolved_path, max_audio_file_size = MAX_AUDIO_FILE_SIZE) : String
      encoded = load_file_as_base64_data(resolved_path, max_audio_file_size)
      unless allowed_audio?(encoded)
        raise AudioLoadingError.new "The file '#{resolved_path}' is not an allowed audio format."
      end

      encoded
    end
  end
end
