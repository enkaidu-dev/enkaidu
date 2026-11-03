require "http/client"
require "uri"
require "sync/exclusive"
require "./chat"
require "./protocol_kind"

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

    private def attempt_post_and_stream(body, session_id : String? = nil, path : String? = nil, &)
      sync.lock do |client|
        resolved_path = path || self.path
        h = headers
        if sid = session_id
          h[Connection.http_session_id_key] = sid
        end
        if ua = Connection.http_user_agent
          h["User-Agent"] = ua
        end
        if TRACE
          STDERR.puts ">>> POST #{resolved_path}"
          STDERR.puts ">>> #{h}"
        end
        client.post(resolved_path, headers: h, body: body) do |resp|
          yield resp
          resp # Always return the response at end of streaming handler block
        end
      rescue ex
        STDERR.puts "<<x #{ex.inspect_with_backtrace}" if TRACE
        @sync = nil
        raise ex
      end
    end

    protected def post_and_stream(body, session_id : String? = nil, path : String? = nil, &)
      STDERR.puts ">>> --- first try" if TRACE
      retry = false
      begin
        attempt_post_and_stream(body, session_id, path) { |resp| yield resp }
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
        attempt_post_and_stream(body, session_id, path) { |resp| yield resp }
      end
    end

    abstract def protocol : ProtocolKind

    protected abstract def url : String

    protected abstract def path : String

    protected abstract def headers : HTTP::Headers

    # The concrete `Chat` implementation to instantiate for the given protocol.
    # `protocol` may be passed explicitly (compatibility override, e.g. forcing
    # ChatCompletions on an OpenAI-compatible backend); `nil` selects the
    # connection's declared (highest-fidelity) protocol.
    def new_chat(&) : LLM::Chat
      chat = case protocol
             when .responses? then LLM::Protocol::Responses::Chat.new(self)
             else                  LLM::Protocol::ChatCompletions::Chat.new(self)
             end
      with chat yield
      chat
    end

    # The wire path the given protocol speaks for *this* connection. By
    # convention the Responses protocol lives at `/v1/responses` on the same
    # host, while ChatCompletions uses this connection's default `path`. A
    # provider may override to keep the path decision local (e.g. Azure's
    # deployment-scoped paths).
    protected def protocol_path(kind : LLM::ProtocolKind) : String
      kind.responses? ? "/v1/responses" : path
    end

    # -------

    @@http_session_id_key = "x-session-id"
    @@http_user_agent : String? = nil

    def self.http_session_id_key
      @@http_session_id_key
    end

    def self.http_user_agent
      @@http_user_agent
    end

    # Allow the agent to set this once
    def self.http_user_agent=(user_agent : String)
      @@http_user_agent = user_agent.downcase
    end
  end
end
