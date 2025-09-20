require "option_parser"
require "json"
require "baked_file_system"
require "mime"

require "./acpa"

require "./enkaidu/*"
require "./enkaidu/cli/*"
require "./enkaidu/wui/*"

require "./sucre/command_parser"
require "./tools/image_helper"

require "./sucre/web_server"

module Enkaidu
  module Server
    class FileStorage
      # extend BakedFileSystem
      # bake_folder "../webui/public"

      def self.get(path)
        File.new("webui/dist#{path}")
      end
    end

    module API
      enum MessageType
        Info
        Warn
        Error
      end

      class Message
        include JSON::Serializable

        getter type : MessageType
        getter message : String

        getter? markdown : Bool
        getter details : String?

        def initialize(@type, @message, @details = nil, @markdown = false); end
      end
    end

    # `Sever` is the interim WIP entry point for the server-mode build of Enkaidu.
    # At some point it will be available via a `--server` switch from the same binary
    class Main
      private getter? done = false
      private getter count = 0
      private getter opts : CLI::Options
      private getter console : SessionRenderer
      private getter queue : EventRenderer

      private getter web_server : WebServer

      private getter session : Session
      private getter commander : SlashCommander

      alias SessionRequests = Symbol | ACPA::Request::PromptParams

      private getter session_work = Channel(SessionRequests).new
      private getter session_done = Channel(Bool).new

      delegate recorder, to: @session

      WELCOME_MSG = "Welcome to Enkaidu (Server Mode)"
      WELCOME     = <<-TEXT
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content, by enabling LLMs
    and connecting with MCP servers.
    TEXT

      def initialize
        @queue = Server::EventRenderer.new

        @console = CLI::ConsoleRenderer.new
        console.info_with WELCOME_MSG, WELCOME, markdown: true
        console.info_with ""

        @opts = CLI::Options.new(console)

        @web_server = WebServer.new(8765)

        queue.info_with(WELCOME_MSG, WELCOME, markdown: true)

        @session = Session.new(queue, opts: opts)
        @commander = SlashCommander.new(session)

        session.auto_load

        prepare_web_server
      end

      private def gather_queue_events
        list = [] of Render::BaseEvent
        while ev = queue.event?
          list << ev
        end
        list
      end

      private def prepare_web_server
        web_server.before_all do |_, resp|
          resp.content_type = "application/json"
        end

        web_server.get "/api/quit" do |_, resp|
          session_work.send(:quit)
          resp.print "{ }"
          web_server.close
        end

        web_server.get "/api/start" do |req, resp|
          STDERR.puts "~~~ req: #{req.inspect}"
          list = gather_queue_events
          list.each { |line| resp.puts line.to_json }
        end

        web_server.post "/api/prompt" do |req, resp|
          if body_io = req.body
            prompt_req = ACPA::Request::PromptParams.from_json(body_io.gets_to_end)
            STDERR.puts "~~~ req: #{prompt_req.inspect}"
            session_work.send(prompt_req)
            session_done.receive
            list = gather_queue_events
            list.each { |line| resp.puts line.to_json }
          else
            raise ArgumentError.new("Nil body: #{req.method} #{req.path}")
          end
        end

        web_server.unknown_get do |req, resp|
          path = req.path == "/" ? "/index.html" : req.path
          if file = FileStorage.get(path)
            resp.content_type = MIME.from_filename(path)
            IO.copy(file, resp)
          else
            raise ArgumentError.new("Unknown request: #{req.method} #{path}")
          end
        end
      end

      # We do all the session requests in the `Main` fibre by waiting for work requests
      # and then signalling the request is done.
      def handle_session_requests
        done = false
        while !done && (req = session_work.receive?)
          case req
          when :quit
            done = true
          when ACPA::Request::PromptParams
            query = req.prompt.first.text.strip
            if query.strip.starts_with? '/'
              commander.make_it_so(query)
            else
              session.ask(query)
            end
            session_done.send(true)
          else
            STDERR.puts "~~~ #handle_session_requests: ?? #{req.inspect}"
          end
        end
      end

      def run
        web_server.start
        console.info_with "INFO: Server started: http://localhost:#{web_server.port}/"
        handle_session_requests
        web_server.join
        console.info_with "Goodbye"
      end
    end
  end
end

{% unless flag?(:test) %}
  Enkaidu::Server::Main.new.run
{% end %}
