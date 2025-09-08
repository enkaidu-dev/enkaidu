require "option_parser"
require "json"
require "baked_file_system"
require "mime"

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

      delegate recorder, to: @session

      WELCOME_MSG = "Welcome to Enkaidu (Server Mode)"
      WELCOME     = <<-TEXT
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content, by enabling LLMs
    and connecting with MCP servers.

    When entering a query,
    - Type `/help` to see the `/` commands available.
    - Press `Alt-Enter` or `Option-Enter` to start multi-line editing.
    TEXT

      def initialize
        @queue = Server::EventRenderer.new

        @console = CLI::ConsoleRenderer.new
        console.info_with WELCOME_MSG
        # console.info_with WELCOME_MSG, WELCOME, markdown: true
        console.info_with ""

        @opts = CLI::Options.new(console)

        @web_server = WebServer.new(8765)
        @session = Session.new(queue, opts: opts)
        @commander = SlashCommander.new(session)

        prepare_web_server
      end

      private def prepare_web_server
        web_server.before_all do |_, resp|
          resp.content_type = "application/json"
        end

        web_server.get "/api/quit" do |_, resp|
          resp.print "{ }"
          web_server.close
        end

        web_server.get "/api/start" do |_, resp|
          # resp.print API::Message.new(API::MessageType::Info, WELCOME_MSG,
          #   details: WELCOME, markdown: true).to_json
          queue.info_with(WELCOME_MSG, WELCOME, markdown: true)
          session.auto_load

          list = [] of Render::BaseEvent
          while ev = queue.event?
            list << ev
          end
          resp.print list.to_json
        end

        web_server.get_unknown do |req, resp|
          path = req.path == "/" ? "/index.html" : req.path
          if file = FileStorage.get(path)
            resp.content_type = MIME.from_filename(path)
            IO.copy(file, resp)
          else
            raise ArgumentError.new("Unknown request: #{req.method} #{path}")
          end
        end
      end

      # private def query(q)
      #   recorder << "," if count.positive?
      #   session.ask(query: q, attach: commander.take_inclusions)
      #   @count += 1
      # end

      # def run
      #   session.auto_load

      #   recorder << "["
      #   while !done?
      #     puts
      #     renderer.show_inclusions(commander.query_indicators)
      #     if q = reader.read_next
      #       case q = q.strip
      #       when .starts_with?("/")
      #         @done = commander.make_it_so(q) == :done
      #       else
      #         query(q)
      #       end
      #     else
      #       @done = true
      #     end
      #   end
      #   recorder << "]"
      # ensure
      #   recorder.close
      # end

      def run
        web_server.start
        console.info_with "INFO: Server started: http://localhost:#{web_server.port}/"
        web_server.join
        console.info_with "Goodbye"
      end
    end
  end
end

{% unless flag?(:test) %}
  Enkaidu::Server::Main.new.run
{% end %}
