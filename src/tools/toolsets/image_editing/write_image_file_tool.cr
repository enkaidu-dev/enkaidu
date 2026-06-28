require "json"
require "base64"
require "../../built_in_function"
require "../../image_helper"

module Tools::ImageEditing
  # The `WriteImageFileTool` class defines a tool for creating image files from base64 encoded data within
  # the current directory.
  class WriteImageFileTool < BuiltInFunction
    name "write_image_file"
    side_effects SideEffects::FileWrite

    description "Write an image file within the current directory with the given base64-encoded image data URL. " \
                "Create entire path to the file if needed. DOES NOT overwrite existing file unless requested."

    param "file_path", type: Param::Type::Str, required: true,
      description: "The relative path where the file will be written."
    param "image_data", type: Param::Type::Str, required: true,
      description: "The base64 encoded image data in the format of a data URL " \
                   "('data:<content_type>;base64,<data>'). Supported content types are: " \
                   "#{ImageHelper::ALLOWED_IMAGE_CONTENT_TYPES.join(',')}"
    param "overwrite", type: Param::Type::Bool, required: false,
      description: "Optional. Set to true to overwrite existing file; default is false."

    param "file_path", type: Param::Type::Str, required: true,
      description: "The relative path where the image file will be created."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include ImageHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"].as_s? ||
                    return error_response("The required file_path was not specified")
        data_url = args["image_data"].as_s? ||
                   return error_response("The required image_data was not specified")
        overwrite = args["overwrite"]?.try(&.as_bool?) || false

        resolved_path = resolve_path(file_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)

        return error_response("The file '#{file_path}' already exists.") if file_exists?(resolved_path) && !overwrite

        begin
          # Parse the data URL
          match = /data:(?<type>image\/\w+);base64,(?<data>.*)/.match(data_url)
          unless match
            return error_response("The provided image data is not a valid data URL.")
          end
          content_type = match["type"]
          base64_data = match["data"]

          # Validate content type using ImageTypeHelper
          determined_type = determine_image_content_type(base64_data)
          unless ALLOWED_IMAGE_CONTENT_TYPES.includes?(content_type) && content_type == determined_type
            return error_response("Unsupported or mismatched image format: #{content_type}. " \
                                  "Detected format: #{determined_type}. Supported formats are PNG and JPEG.")
          end

          decoded_data = Base64.decode(base64_data)

          File.write(resolved_path, decoded_data)
          success_response(file_path)
        rescue ex
          error_response("An error occurred while writing the image file: #{ex.message}")
        end
      end

      private def success_response(file_path)
        {message: "Image file '#{file_path}' written successfully."}.to_json
      end

      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
