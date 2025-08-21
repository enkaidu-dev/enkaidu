module Sucre
  class ImageTypeHelper
    # Magic bytes for PNG and JPEG
    # Base64-encoded magic bytes
    PNG_MAGIC_BASE64            = "iVBORw0KGgo="
    JPEG_MAGIC_BASE64           = "/9j/"
    PNG_MAGIC_BASE64_NO_PADDING = "iVBORw0KGgo"

    # Determines the content type based on the magic bytes of the image
    def self.determine_content_type(base64_encoded_string : String) : String
      # Check the base64 string for encoded magic bytes
      if base64_encoded_string.starts_with?(PNG_MAGIC_BASE64) || base64_encoded_string.starts_with?(PNG_MAGIC_BASE64_NO_PADDING)
        return "image/png"
      elsif base64_encoded_string.starts_with?(JPEG_MAGIC_BASE64)
        return "image/jpeg"
      else
        return "unknown"
      end
    end
  end
end
