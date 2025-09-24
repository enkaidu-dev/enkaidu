require "option_parser"
require "json"
require "baked_file_system"
require "mime"

require "../../acpa"
require "../../sucre/web_server"

require "../cli/options"
require "../cli/console_renderer"

require "./event_renderer"
require "./work"

require "../slash_commander"
require "../session"

module Enkaidu
  module WUI
    class FileStorage
      {% if flag?(:release) %}
        # Build the disttibution build of webUI into the executable
        extend BakedFileSystem
        bake_folder "../webui/dist"
      {% else %}
        # Reads files from file system in debug mode
        def self.get(path)
          File.new("webui/dist#{path}")
        end
      {% end %}
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

      private getter session_requests = Channel(SessionRequests).new(2)
      private getter session_work = Channel(Work).new(10)

      delegate recorder, to: @session

      WELCOME_MSG = "Welcome to Enkaidu (WebUI Server Mode)"
      WELCOME     = <<-TEXT
    This is your second-in-command(-line) designed to assist you with
    writing & maintaining code and other text-based content, by enabling LLMs
    and connecting with MCP servers.
    TEXT

      def initialize(@opts)
        @console = opts.renderer

        @queue = EventRenderer.new(session_work)

        console.info_with WELCOME_MSG, WELCOME, markdown: true
        console.info_with ""

        @web_server = WebServer.new(8765)

        queue.info_with(WELCOME_MSG, WELCOME, markdown: true)

        @session = Session.new(queue, opts: opts)
        @commander = SlashCommander.new(session)

        session.auto_load

        prepare_web_server
      end

      private def gather_queue_events
        list = [] of Render::Event
        while ev = queue.event?
          list << ev
        end
        list
      end

      private def prepare_web_server
        web_server.before_all do |req, resp|
          resp.content_type = "application/json"
          STDERR.puts "#{req.method} #{req.path}".colorize(:green)
        end

        web_server.get "/api/start" do |_, resp|
          list = gather_queue_events
          list.each { |line| resp.puts line.to_json }
        end

        web_server.post "/api/prompt" do |req, resp|
          if body_io = req.body
            prompt_req = ACPA::Request::PromptParams.from_json(body_io.gets_to_end)
            channel_acpa_session_request(prompt_req, resp)
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

      # Call this with an ACPA request to make sure it gets to the right
      # fibre and is handled by the request dispatcher
      private def channel_acpa_session_request(req : ACPA::Request::ParamTypes, resp : HTTP::Server::Response)
        session_requests.send(req)
        # Monitor session work and gather queue events when triggered;
        while work = session_work.receive
          list = gather_queue_events
          list.each { |line| resp.puts line.to_json }
          resp.flush
          # and exit when the original request is done.
          break if work.request_handled?
        end
      end

      # Do not call this directly from a server request handler; use
      # #channal_acpa_session_request to use async channels to dispatch
      # request and gather up responses
      private def handle_prompt_request(req : ACPA::Request::PromptParams)
        query = req.prompt.first.text.strip
        if query.strip.starts_with? '/'
          if commander.make_it_so(query) == :done
            queue.info_with("GOOD BYE!")
            session_requests.send(:quit)
          end
        else
          session.ask(query)
        end
      end

      # Do not call this directly from a server request handler.
      private def dispatch_acpa_requests(req : ACPA::Request::ParamTypes)
        # STDERR.puts "#dispatch_acpa_requests: #{req.inspect}".colorize(:yellow)
        case req
        when ACPA::Request::PromptParams then handle_prompt_request(req)
        else
          STDERR.puts "~~~ #handle_session_requests: Unknown ACPA requets: #{req.inspect}".colorize(:red)
        end
      ensure
        # Always do this; without this the server request handler will get stuck and all
        # other requests will get stuck.
        session_work.send(Work::RequestHandled)
      end

      # Do not call this directly from a server request handler.
      # We do all the session requests in the `Main` fibre by waiting for work requests
      # and then signalling the request is done.
      private def wait_and_handle_session_requests
        done = false
        while !done && (req = session_requests.receive?)
          # STDERR.puts "#wait_and_handle_session_requests: #{req.inspect}".colorize(:yellow)
          case req
          when :quit                     then done = true
          when ACPA::Request::ParamTypes then dispatch_acpa_requests(req)
          else
            STDERR.puts "~~~ #handle_session_requests: ?? #{req.inspect}"
          end
        end
        web_server.close
      end

      def run
        web_server.start
        console.info_with "INFO: WebUI server started: http://localhost:#{web_server.port}/"
        wait_and_handle_session_requests
        web_server.join
        console.info_with "Goodbye"
      end
    end
  end
end
