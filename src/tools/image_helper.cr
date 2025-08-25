require "./file_helper"

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

  # Determines the content type based on the magic bytes of the image
  def determine_image_content_type(base64_encoded_string : String) : String
    # Check the base64 string for encoded magic bytes
    ALLOWED_IMAGE_MAGIC_B64.each_with_index do |magic, i|
      return ALLOWED_IMAGE_CONTENT_TYPES[i] if base64_encoded_string.starts_with?(magic)
    end
    "unknown"
  end
end
