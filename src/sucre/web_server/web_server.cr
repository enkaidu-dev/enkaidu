require "http/server"
require "json"

class WebServer
  private enum Tracker
    StartHandler
    EndHandler
    EndServer
  end

  getter port : Int32
  getter address : Socket::IPAddress

  private alias HandlerProc = Proc(HTTP::Request, HTTP::Server::Response, Nil)

  private getter routers = {} of String => HandlerProc
  private getter work_tracker = Channel(Tracker).new
  private getter work_finished = Channel(Bool).new
  private getter active_handlers = 0

  def initialize(@port, bind_to_all_nics = false)
    @server = HTTP::Server.new do |context|
      handle(context)
    end
    @address = if bind_to_all_nics
                 @server.bind_tcp "0.0.0.0", port
               else
                 @server.bind_tcp port
               end
  end

  private def start_tracking
    spawn do
      loop do
        msg = work_tracker.receive?
        break if msg.nil? || msg.end_server?

        case msg
        when .start_handler? then @active_handlers += 1
        when .end_handler?   then @active_handlers -= 1
        end
      end
      work_finished.send(true)
    end
  end

  private def start_listening
    spawn do
      @server.listen
      @work_tracker.send(Tracker::EndServer)
    end
  end

  private getter before_handler : HandlerProc?

  def before_all(&block : HandlerProc)
    @before_handler = block
  end

  def get(path, &handler : HTTP::Request, HTTP::Server::Response -> Nil)
    routers["GET #{path}"] = handler
  end

  def unknown_get(&handler : HTTP::Request, HTTP::Server::Response -> Nil)
    routers["GET *"] = handler
  end

  def post(path, &handler : HTTP::Request, HTTP::Server::Response -> Nil)
    routers["POST #{path}"] = handler
  end

  private def handle(context)
    work_tracker.send(Tracker::StartHandler)
    route = "#{context.request.method} #{context.request.path}"
    if handler = (routers[route]? || routers["#{context.request.method} *"]?)
      if pre_handler = before_handler
        pre_handler.call(context.request, context.response)
      end
      handler.call(context.request, context.response)
    else
      raise ArgumentError.new("Unknown route: #{route}")
    end
  rescue ex
    STDERR.puts "ERROR: --------"
    STDERR.puts ex.inspect_with_backtrace
    context.response.content_type = "application/json"
    context.response.status_code = 500
    context.response.print <<-ERROR
        { "type" : "error", "message" : "#{ex}" }
        ERROR
  ensure
    work_tracker.send(Tracker::EndHandler)
  end

  def close
    @server.close
  end

  def start
    start_tracking
    start_listening
  end

  def join
    work_finished.receive?
  end
end
