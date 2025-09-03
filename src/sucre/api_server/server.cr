require "http/server"

class Server
  enum Tracker
    StartHandler
    EndHandler
    EndServer
  end

  getter port : Int32
  getter address : Socket::IPAddress

  private getter work_tracker = Channel(Tracker).new
  private getter work_finished = Channel(Bool).new

  private getter active_handlers = 0

  def initialize(@port)
    @server = HTTP::Server.new do |context|
      handle(context)
    end
    @address = @server.bind_tcp port
  end

  private def start_tracking
    spawn do
      while true
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

  private def handle(context)
    work_tracker.send(Tracker::StartHandler)
    puts "~~~ request: #{context.request.inspect}"
    context.response.content_type = "text/plain"
    context.response.print "Hello world!"
    if context.request.path == "/quit"
      @server.close
    end
  ensure
    work_tracker.send(Tracker::EndHandler)
  end

  def run
    start_tracking
    start_listening
  end

  def wait
    work_finished.receive?
  end
end

s = Server.new(8080)
s.run
puts s.wait.inspect
