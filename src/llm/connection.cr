require "http/client"
require "uri"
require "sync/exclusive"
require "./chat"

module LLM
  # Error raised by connection when protocol needs an API key
  class MissingAPIKey < Exception; end

  # `Connection` is an abstract class that defines the basic structure
  # for chat connection implementations.
  abstract class Connection
    protected property model : String? = nil

    # Keep client exclusive to avoid concurrent calls to same client
    @sync : Sync::Exclusive(HTTP::Client)?

    def initialize; end

    private def connect
      Sync::Exclusive.new(HTTP::Client.new(URI.parse(url)))
    end

    private def sync
      @sync ||= connect
    end

    private def attempt_post_and_stream(body, &)
      sync.lock do |client|
        if TRACE
          STDERR.puts ">>> POST #{path}"
          STDERR.puts ">>> #{headers}"
        end
        client.post(path, headers,
          body: body) do |resp|
          yield resp
          resp # Always return the response at end of streaming handler block
        end
      rescue ex
        STDERR.puts "<<x #{ex.inspect_with_backtrace}" if TRACE
        @sync = nil
        raise ex
      end
    end

    protected def post_and_stream(body, &)
      STDERR.puts ">>> --- first try" if TRACE
      retry = false
      begin
        attempt_post_and_stream(body) { |resp| yield resp }
      rescue
        retry = true
      end
      # One retry allowed when an IO error occurs.
      # Usually IO errors cannot be retried away.
      # But "some" LLM servers seem to have a very short
      #   keep-alive for connections which can only be overcome
      #   by retrying at least once.
      if retry
        STDERR.puts ">>> --- the one and only retry".colorize(:red) if TRACE
        attempt_post_and_stream(body) { |resp| yield resp }
      end
    end

    protected abstract def url : String

    protected abstract def path : String

    protected abstract def headers : HTTP::Headers

    abstract def new_chat(&) : Chat
  end
end
