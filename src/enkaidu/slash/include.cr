require "./command"
require "../../tools/image_helper"

module Enkaidu::Slash
  class IncludeCommand < Command
    include Tools::ImageHelper

    # Track any query indicators
    getter query_indicators = [] of String

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
    HELP1

    def name : String
      NAME
    end

    def help : String
      HELP
    end

    # Returns a `ChatInclusions` if present, removing it from the command state.
    # I.e. This method will clear the inclusions held by this command.
    def take_inclusions!
      hold = @inclusions
      @inclusions = nil
      @query_indicators.clear
      hold
    end

    # Current inclusions collector
    private def inclusions
      @inclusions ||= LLM::ChatInclusions.new
    end

    def handle(session_manager : SessionManager, cmd : CommandParser)
      session = session_manager.session
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
