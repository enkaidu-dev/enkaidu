require "http/client"
require "uri"
require "sync/exclusive"
require "./chat"

module LLM
  # `Connection` is an abstract class that defines the basic structure
  # for chat connection implementations.
  abstract class Connection
    protected property model : String? = nil

    # Keep client exclusive to avoid concurrent calls to same client
    @sync : Sync::Exclusive(HTTP::Client)

    def initialize
      @sync = Sync::Exclusive.new(HTTP::Client.new(URI.parse(url)))
    end

    protected def post_and_stream(body, &)
      @sync.lock do |client|
        if TRACE
          STDERR.puts ">>> POST #{path}" if TRACE
          STDERR.puts ">>> #{headers}" if TRACE
        end
        client.post(path, headers,
          body: body) do |resp|
          yield resp
          resp # Always return the response at end of streaming handler block
        end
      end
    end

    protected abstract def url : String

    protected abstract def path : String

    protected abstract def headers : HTTP::Headers

    abstract def new_chat(&) : Chat
  end
end
