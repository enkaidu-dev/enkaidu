require "base64"

require "./file_helper"

module Tools
  class ImageLoadingError < Exception; end

  module ImageHelper
    include FileHelper

    # Allowed image content types
    ALLOWED_IMAGE_CONTENT_TYPES = ["image/png", "image/jpeg"]

    # Allowed image formats
    ALLOWED_IMAGE_FORMATS = ["PNG", "JPEG"]

    # Base64-encoded magic bytes for allowed image formats,
    # without padding so we can do prefix checking.
    ALLOWED_IMAGE_MAGIC_B64 = [
      "iVBORw0KGgo", # PNG
      "/9j/",        # JPEG
    ]

    UNKNOWN_IMAGE_TYPE = "unknown"

    # Determines the content type based on the magic bytes of the image
    def determine_image_content_type(base64_encoded_string : String) : String
      # Check the base64 string for encoded magic bytes
      ALLOWED_IMAGE_MAGIC_B64.each_with_index do |magic, i|
        return ALLOWED_IMAGE_CONTENT_TYPES[i] if base64_encoded_string.starts_with?(magic)
      end
      UNKNOWN_IMAGE_TYPE
    end

    def allowed_image?(base64_encoded_string : String)
      determine_image_content_type(base64_encoded_string) != UNKNOWN_IMAGE_TYPE
    end

    # Returns a data URL for the image in the file; assumes path is allowed; raises
    # errors if unable to open file or if content is not an allowed image
    def load_image_file_as_data_url(resolved_path) : String
      content = File.read(resolved_path)
      encoded = Base64.strict_encode(content)
      determined_type = determine_image_content_type(encoded)

      if determined_type == UNKNOWN_IMAGE_TYPE
        raise ImageLoadingError.new "The file '#{resolved_path}' is not an image."
      end

      "data:#{determined_type};base64,#{encoded}"
    end
  end
end
