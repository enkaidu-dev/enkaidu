require "./enkaidu/session"

module Enkaidu
  class Main
    private getter session
    private getter? done = false
    private getter count = 0

    def initialize
      @session = Session.new
      if session.streaming?
        puts "WARNING: No chat output when streaming is enabled (for now). Sorry.".colorize(:yellow)
      end
    end

    private def commands(q)
      case q
      when "/bye" then @done = true
      else
        session.warning("ERROR: Unknown command: #{q}")
      end
    end

    private def query(q)
      session.log "," if count.positive?
      session.ask(query: q)
      @count += 1
      puts
    end

    def run
      begin
        session.log "["
        while !done?
          print "----\nQUERY > ".colorize(:yellow)
          if (q = gets)
            case (q = q.strip)
            when .starts_with?("/") then commands(q)
            else
              query(q)
            end
          else
            session.warning("ERROR: Unexpected end of input IO")
            @done = true
          end
        end
        session.log "]"
      ensure
        session.log_close
      end
    end
  end
end

Enkaidu::Main.new.run
