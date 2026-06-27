require "json"
require "../../built_in_function"
require "../../audio_helper"

module Tools::AudioEditing
  # The `ReadAudioFileTool` class defines a tool for reading an audio file and returning it as a base64 audio attachment.
  # It ensures the operation is performed securely within the allowed directory, avoiding access to unauthorized paths.
  class ReadAudioFileTool < BuiltInFunction
    name "read_audio_file"
    side_effects SideEffects::FileRead

    # Provide a description for the tool
    description "Reads the content of a specified audio file in the current directory and returns it as base64 encoded text. " \
                "Supports the following audio formats: #{AudioHelper::ALLOWED_AUDIO_FORMATS.join(',')}. "

    # Define the acceptable parameter using the `param` method
    param "file_path", type: Param::Type::Str, required: true,
      description: "The relative path to the audio file to read."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include AudioHelper

      def execute(args : JSON::Any) : LLM::Function::Reply | String
        file_path = args["file_path"].as_s? || return error_response("The required file_path was not specified")

        resolved_path = resolve_path(file_path)

        return error_response("Access to the specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)

        begin
          encoded = load_audio_file_as_data(resolved_path)
          determined_format = determine_audio_format(encoded)

          unless allowed_audio?(encoded)
            return error_response("The specified file '#{file_path}' is not allowed audio file.")
          end

          success_response(file_path, encoded, determined_format)
        rescue e
          error_response("An error occurred while reading the file: #{e.message}")
        end
      end

      # Create a success response as a JSON string
      def success_response(file_path, data, format)
        reply = LLM::Function::Reply.new("Audio read from '#{file_path}' will be sent separately.")
        reply.attach_audio(data, format)
        reply
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end
    end
  end
end
