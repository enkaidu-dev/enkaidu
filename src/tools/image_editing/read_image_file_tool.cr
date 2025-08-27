require "json"
require "base64"
require "../image_editing"

module Tools::ImageEditing
  # The `ReadImageFileTool` class defines a tool for reading an image file and returning it as a data URL.
  # It ensures the operation is performed securely within the allowed directory, avoiding access to unauthorized paths.
  class ReadImageFileTool < BuiltInFunction
    name "read_image_file"

    # Provide a description for the tool
    description "Reads the content of a specified image file in the current directory and returns it as a base64 encoded data URL string. " \
                "Supports the following image formats: #{ImageHelper::ALLOWED_IMAGE_FORMATS.join(',')}. " \
                "Ensures the file is within the current directory and is a valid image file."

    # Define the acceptable parameter using the `param` method
    param "file_path", type: LLM::ParamType::Str, description: "The relative path to the image file to read.", required: true

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include ImageHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"].as_s? || return error_response("The required file_path was not specified")

        resolved_path = resolve_path(file_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)

        begin
          content = File.read(resolved_path)
          encoded = Base64.strict_encode(content)
          determined_type = determine_image_content_type(encoded)

          unless ALLOWED_IMAGE_CONTENT_TYPES.includes?(determined_type)
            return error_response("The specified file '#{file_path}' is not an image file.")
          end

          success_response(file_path, "data:#{determined_type};base64,#{encoded}")
        rescue e
          error_response("An error occurred while reading the file: #{e.message}")
        end
      end

      # Create a success response as a JSON string
      def success_response(file_path, data_url)
        {
          file_path:  file_path,
          image_data: data_url,
        }.to_json
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
