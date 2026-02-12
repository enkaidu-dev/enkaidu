require "./command"
require "../../tools/image_helper"

module Enkaidu::Slash
  class IncludeCommand < Command
    include Tools::ImageHelper

    # Track any query indicators
    getter query_indicators = [] of String

    # Track response schema, if any
    getter response_json_schema : LLM::ResponseSchema? = nil

    NAME = "/include"

    HELP = <<-HELP1
    `#{NAME} [<sub-command>]`
    - `image_file <PATH>`
      - Prepare image data from a file to _include_ with the next query;
        make sure the LLM model supports vision/image processing.
    - `text_file <PATH>`
      - Prepare text from a file to _include_ with the next query.
    - `any_file <PATH>`
      - Prepare a file (with it's base name) to _include_ with the next query;
        make sure the LLM model supports file data along.
    - `response_json_schema <PATH>`
      - Use the given file as the JSON schema description to tell the model that the
        next request's response should be a JSON object matching the schema.
      - The input should be a file with a JSON object defined as follows:
        `{ "name" : <string>, "description": <string>, "strict": <bool>, "schema": <object> }`
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    # Returns a `ChatInclusions` if present, removing it from the command state.
    # The response schema is not cleared
    def take_inclusions!
      hold = @inclusions
      @inclusions = nil
      @query_indicators.clear
      hold
    end

    # Returns the `ResponseSchema` if present, removing it from the command state.
    # The inclusions are not cleared.
    def take_response_schema!
      schema = @response_json_schema
      @response_json_schema = nil
      schema
    end

    # Current inclusions collector
    private def inclusions
      @inclusions ||= LLM::ChatInclusions.new
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.current.session
      begin
        ok = nil
        if filepath = cmd.arg_at?(2).try(&.as(String))
          basename = Path.new(filepath).basename
          if cmd.expect? NAME, "image_file", String
            inclusions.image_data load_image_file_as_data_url(filepath), basename
            ok = query_indicators << "I:#{basename}"
          elsif cmd.expect? NAME, "text_file", String
            inclusions.text File.read(filepath), basename
            ok = query_indicators << "T:#{basename}"
          elsif cmd.expect? NAME, "any_file", String
            inclusions.file_data load_file_as_data_url(filepath), basename
            ok = query_indicators << "F:#{basename}"
          elsif cmd.expect? NAME, "response_json_schema", String
            @response_json_schema = LLM::ResponseSchema.from_json(File.read(filepath))
            ok = true
          end
        end
        session.renderer.warning_with(
          "ERROR: Unknown or incomplete sub-command: '#{cmd.input}'",
          help: HELP, markdown: true) if ok.nil?
      rescue e
        session.renderer.warning_with("ERROR: #{e.message}",
          help: HELP, markdown: true)
      end
    end
  end
end
