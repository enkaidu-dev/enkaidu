require "option_parser"
require "markterm"

require "../llm"
require "../tools"
require "./logger"

require "./options"

module Enkaidu
  class Session
    include Helpers

    private getter opts = Options.new
    private getter connection : LLM::ChatConnection
    private getter chat : LLM::Chat
    private getter logger : Logger

    def initialize
      @logger = Logger.new(opts.log_file)

      @connection = case opts.provider_name
                    when "azure_openai" then LLM::AzureOpenAI::ChatConnection.new
                    when "ollama"       then LLM::Ollama::ChatConnection.new
                    else
                      error_with "ERROR: Unknown provider: #{opts.provider_name}"
                    end

      @chat = connection.new_chat do
        unless (m = opts.model_name).nil?
          with_model m
        end
        with_debug if opts.debug?
        with_streaming if opts.stream?
        with_system_message "You are a capable coding assistant with the ability to use tool calling to solve complicated multi-step tasks."
        with_tool ListFilesTool.new
        with_tool ReadTextFileTool.new
        with_tool CreateTextFileTool.new
        with_tool ReplaceTextInTextFileTool.new
        with_tool RenameFileTool.new
      end
    end

    private def process_event(r, tools)
      case r["type"]
      when "tool_call"
        tools << r["content"]
        print "  CALL".colorize(:green)
        puts " #{r["content"].dig("function", "name").as_s.colorize(:red)} with #{r["content"].dig("function", "arguments").colorize(:red)}" unless chat.streaming?
      when "text"
        puts "----".colorize(:green)
        puts Markd.to_term(r["content"].as_s) unless chat.streaming?
      when .starts_with? "error"
        warning("ERROR:\n#{r["content"].to_json}")
      end
    end

    def ask(query, render_query = false)
      log "["
      ix = 0
      tools = [] of JSON::Any
      # ask and handle the initial query and its events
      if render_query
        puts "QUERY".colorize(:yellow)
        puts query
      end
      chat.ask query do |event|
        unless event["type"] == "done"
          log "," if ix.positive?
          log event.to_json
          ix += 1
          process_event(event, tools)
        end
      end
      # deal with any tool calls and subsequent events repeatedly until
      # no more tool calls remain
      until tools.empty?
        calls = tools
        tools = [] of JSON::Any
        chat.call_tools_and_ask calls do |event|
          unless event["type"] == "done"
            log "," if ix.positive?
            log event.to_json
            ix += 1
            process_event(event, tools)
          end
        end
      end
      log "]"
    end

    delegate streaming?, to: @chat
    delegate debug?, to: @opts
    delegate log, to: @logger
    delegate log_close, to: @logger
  end
end
