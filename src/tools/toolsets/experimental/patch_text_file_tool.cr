require "json"
require "../../built_in_function"
require "../../file_helper"

module Tools::Experimental
  class PatchTextFileTool < BuiltInFunction
    name "apply_patch_to_text_file"

    PATCHVER = `patch -v`.strip

    description "Applies a patch using the diff format to a specified text file using the " +
                "`patch` command (version `#{PATCHVER}`). " +
                "Ensures the file is within the current directory and is a text file."

    param "file_path", type: LLM::ParamType::Str,
      description: "The relative path to the file to be patched.", required: true
    param "patch_content", type: LLM::ParamType::Str,
      description: "The content of the patch to apply.", required: true

    # Replace `runner` macro to create with self
    def new_runner : Runner
      Runner.new(self)
    end

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      include FileHelper

      private getter func : PatchTextFileTool

      def initialize(@func); end

      def execute(args : JSON::Any) : String
        file_path = args["file_path"]?.try &.as_s? || return error_response("The required file_path was not specified")
        patch_content = args["patch_content"]?.try &.as_s? || return error_response("The required patch_content was not specified")

        resolved_path = resolve_path(file_path)

        return error_response("The specified path '#{file_path}' is not allowed.") unless within_current_directory?(resolved_path)
        return error_response("The specified file '#{file_path}' does not exist.") unless valid_file?(resolved_path)

        begin
          stdout = IO::Memory.new
          stdin = IO::Memory.new(patch_content)
          status = Process.run("patch", ["--no-backup-if-mismatch", resolved_path], input: stdin, output: stdout)
          result = stdout.to_s

          STDERR.puts "~~~ pwd: #{FileUtils.pwd}"
          if status.exit_code != 0
            func.renderer.warning_with(
              message: "ERROR: Failed to apply patch.",
              markdown: true,
              help: <<-DEETS
              Exit code #{status.exit_code} (`#{status}`)
              #### Patch input

              ```
              #{patch_content}
              ```

              #### Command output

              ```
              #{result.gsub(FileUtils.pwd, ".")}
              ```

              DEETS
            )
            return error_response("Failure: #{result}")
          end
          success_response(file_path)
        rescue e
          error_response("An error occurred while applying the patch: #{e.message}")
        end
      end

      private def error_response(message)
        {"error" => message}.to_json
      end

      private def success_response(file_path)
        {"file_path" => file_path, "message" => "Patch applied successfully"}.to_json
      end
    end
  end
end
