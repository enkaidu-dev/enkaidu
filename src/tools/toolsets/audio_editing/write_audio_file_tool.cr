require "json"
require "base64"
require "../../built_in_function"
require "../../audio_helper"

module Tools::AudioEditing
  # The `WriteAudioFileTool` class defines a tool for creating / over-writing audio files from base64 encoded data, within the current
  # directory.
  class WriteAudioFileTool < BuiltInFunction
    name "create_audio_file"
    side_effects SideEffects::FileWrite

    description "Write audio file within the current directory with the given base64-encoded audio data. " \
                "Create entire path to the file if needed. DOES NOT overwrite existing file unless requested."

    param "file_path", type: Param::Type::Str, required: true,
      description: "The relative path where the file will be written."
    param "audio_data", type: Param::Type::Str, required: true,
      description: "The base64 encoded audio data. Supported audio formats are: " \
                   "#{AudioHelper::ALLOWED_AUDIO_FORMATS.join(',')}"
    param "overwrite", type: Param::Type::Bool, required: false,
      description: "Optional. Set to true to overwrite existing file; default is false."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include AudioHelper

      def execute(args : JSON::Any) : String
        file_path = args["file_path"].as_s? ||
                    return error_response("The required file_path was not specified")
        audio_data = args["audio_data"].as_s? ||
                     return error_response("The required audio_data was not specified")
        overwrite = args["overwrite"]?.try(&.as_bool?) || false

        resolved_path = resolve_path(file_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)

        return error_response("The file '#{file_path}' already exists.") if file_exists?(resolved_path) && !overwrite

        begin
          # Validate content type using ImageTypeHelper
          determined_format = determine_audio_format(audio_data)
          unless determined_format != UNKNOWN_AUDIO_FORMAT
            return error_response("Unknown audio format. Format must be one of: #{ALLOWED_AUDIO_FORMATS.join(", ")}")
          end

          decoded_data = Base64.decode(audio_data)
          File.write(resolved_path, decoded_data)

          success_response(file_path)
        rescue ex
          error_response("An error occurred while creating the image file: #{ex.message}")
        end
      end

      private def success_response(file_path)
        {message: "Audio file '#{file_path}' written successfully."}.to_json
      end

      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
