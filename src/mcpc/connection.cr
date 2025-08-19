require "uri"

require "./http_transport"
require "./session"
require "./sensitive_data"

module MCPC
  # This `ResultError` exception is raised for errors within the
  # JSON-RPC result from the MCP server
  class ResultError < Exception
    getter data : JSON::Any

    def initialize(message, @data)
      super(message)
    end
  end

  # This `ResponseError` exception is raised for errors due to the
  # server's HTTP response contents.
  class ResponseError < Exception
    getter details : Transport::ErrorDetails

    def initialize(message, @details)
      super(message)
    end
  end

  # This MCP connection encapsulates `HttpTransport` and `Session`, adding additional
  # processing and awareness.
  # Usage example:
  # ```
  # mcp = MCPC::HttpConnection.new(ECHO)
  # puts mcp.list_tools
  # puts mcp.call_tool("echo", Hash{"message" => "Hello, world!"})
  # ```
  class HttpConnection
    getter uri : URI
    getter? supports_roots = false
    getter? supports_tools = false
    getter? supports_resources = false
    getter? supports_prompts = false
    getter server_name : String = "UNKNOWN"
    getter server_version : String = "UNKNOWN"
    getter? tracing = false
    private getter auth_token : AuthToken?
    private getter transport : Transport
    private getter session : Session

    # Sets up the MCP connection
    def initialize(url, @tracing = false, @auth_token = nil)
      @uri = URI.parse(url)
      @transport = choose_transport(uri)
      @session = Session.new
      get_ready
    end

    # Enable / disable tracing from this point on
    def tracing=(trace : Bool)
      @tracing = trace
      @transport.tracing = trace
    end

    # This will try to use the legacy transport and then fall back to
    # standard one. (Yes, this is ass backwards, but that's what the spec wants.)
    private def choose_transport(uri)
      STDERR.puts "~~ MCP (Connection#choose_transport) #{uri}".colorize(:yellow) if tracing?
      HttpLegacyTransport.new(uri, tracing: tracing?)
    rescue ex
      STDERR.puts "~~ MCP (Connection) #{ex}".colorize(:yellow) if tracing?
      STDERR.puts "~~    Switch to modern".colorize(:yellow) if tracing?
      HttpTransport.new(uri, tracing: tracing?)
    end

    # Returns an array of tools, if any
    def list_tools : JSON::Any?
      STDERR.puts "---------- Connection#list_tools" if tracing?
      transport.post(session.body_tools_list) do |reply|
        case reply
        when JSON::Any
          if tools = reply.dig?("result", "tools")
            return tools
          end
          raise ResultError.new("Result has no 'tools'; see .data.", reply)
        else
          raise ResponseError.new("Unexpected transport response; see .details.", reply)
        end
      end
    end

    # Calls a tool and returns the content from the reply on success
    def call_tool(name : String,
                  args : Hash(String, String | Number | Bool | JSON::Any)) : JSON::Any?
      STDERR.puts "---------- Connection#call_tool" if tracing?
      transport.post(session.body_tools_call(name, args)) do |reply|
        case reply
        when JSON::Any
          if content = reply.dig?("result", "content")
            return content
          end
          raise ResultError.new("Result has no 'content'; see .data.", reply)
        else
          raise ResponseError.new("Unexpected transport response; see .details.", reply)
        end
      end
    end

    # Returns a JSON representation of the state of this connection
    def to_s(io)
      JSON.build(io) do |json|
        json.object do
          json.field "uri", uri.to_s
          json.field "server" do
            json.object do
              json.field "name", server_name
              json.field "version", server_version
            end
          end
          json.field "supports" do
            json.object do
              json.field "roots", supports_roots?
              json.field "tools", supports_tools?
              json.field "resources", supports_resources?
              json.field "prompts", supports_prompts?
            end
          end
        end
      end
    end

    # Reset to re-initialize the connection whenever calls fail with a 404 error; sets up a new transport and session, and initializes the
    # session. TODO better handling of reset scenarios.
    def reset
      @transport = @transport.class.new(uri)
      @session = Session.new
      get_ready
    end

    # Initializes the session and collects properties
    private def get_ready
      init_ok = false
      STDERR.puts "---------- Connection#get_ready" if tracing?
      transport.post(session.body_initialize) do |reply|
        case reply
        when JSON::Any
          if value = reply.dig?("result", "protocolVersion")
            version = value.as_s
            session.protocol_version = version
            transport.mcp_protocol_version = version
          end
          capabilities = reply.dig("result", "capabilities")
          @supports_roots = capabilities["roots"]? != nil
          @supports_tools = capabilities["tools"]? != nil
          @supports_prompts = capabilities["prompts"]? != nil
          @supports_resources = capabilities["resources"]? != nil
          if server = reply.dig?("result", "serverInfo")
            @server_name = server["name"].as_s
            @server_version = server["version"].as_s
          end
          init_ok = true
        else
          raise ResponseError.new("Unexpected transport response; see .details.", reply)
        end
      end
      # notify init success
      return unless init_ok
      transport.notify(session.body_notify_initialized) do |_|
      end
    end
  end
end
