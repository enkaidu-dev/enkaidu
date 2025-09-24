require "io"
require "colorize"

require "./protocol"

module ACPA
  class Session
    getter id : String

    def initialize(@id); end
  end

  # Singleton, one instance process
  class Agent
    @@the_one : Agent?

    def self.zero
      @@the_one ||= self.new
    end

    getter input : IO
    getter output : IO

    private getter sessions = {} of String => Session

    private def initialize
      @input = STDIN
      @output = STDOUT
    end

    # Listen for JSON RPC requests and process them
    def listen(&) : Nil
      input.each_line do |line|
        line = line.strip
        unless line.empty?
          req = JsonRpcRequest.from_json(line)
          trace line, req
          yield req
        end
      end
    end

    private def trace(line, req)
      STDERR.puts line.colorize(:yellow)
      STDERR.puts "class: #{req.class.colorize(:cyan)}"
      STDERR.puts "clean: #{req.clean?.colorize(:cyan)}"
      STDERR.puts "unmapped: #{req.inspect.colorize(:red)}" if req.dirty?
      STDERR.puts
      STDERR.puts req.to_pretty_json("  ")
      STDERR.puts "------"
    end
  end
end

ACPA::Agent.zero.listen { |_| }
