require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# A no-op Transport implementation for mock connections.
class MockMcpTransport < MCPC::Transport
  property mcp_protocol_version : String? = nil

  def close; end
  def post(body, & : JSON::Any | MCPC::Transport::ErrorDetails ->); end
  def notify(body, & : JSON::Any | MCPC::Transport::ErrorDetails ->); end
end

# A minimal MCPC::HttpConnection subclass that only initializes the URI.
# We never call methods on @transport or @session in the save path.
class MockMcpConnection < MCPC::HttpConnection
  def initialize(url : String)
    @uri = URI.parse(url)
    @transport_type = MCPC::TransportType::ModernHTTP
    @transport = MockMcpTransport.new
    @session = MCPC::JsonRpcSession.new
  end
end

class McpSaveProbeSession < EnkaiduWiretapTestSession
  def add_mcp_connection(conn : MCPC::HttpConnection)
    @mcp_connections << conn
  end
end

Spectator.describe "Enkaidu::Session save_active_mcp_servers" do
  include EnkaiduSessionWiretapHelpers

  def new_session
    renderer = EnkaiduWiretapTestRenderer.new
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = McpSaveProbeSession.new(renderer, options)
    {session, renderer}
  end

  it "warns and omits servers not found in config by URL" do
    with_ollama_envs do
      session, renderer = new_session
      session.add_mcp_connection(MockMcpConnection.new("http://unknown:9999"))

      io = IO::Memory.new
      session.save_session(io)
      io.rewind

      lines = io.each_line.to_a
      expect(lines.size).to eq(4)

      # Line 2: MCP servers — the unknown server should be omitted
      mcp = JSON.parse(lines[1])
      expect(mcp["mcp_servers"]).to eq([] of JSON::Any)

      # The renderer should have received a warning
      expect(renderer.warnings.size).to eq(1)
      expect(renderer.warnings.first.includes?("MCP server not in config cannot be saved with session")).to be_truthy
      expect(renderer.warnings.first.includes?("http://unknown:9999")).to be_truthy
    end
  end

  it "writes empty mcp_servers array when no connections exist" do
    with_ollama_envs do
      session, renderer = new_session

      io = IO::Memory.new
      session.save_session(io)
      io.rewind

      lines = io.each_line.to_a
      expect(lines.size).to eq(4)

      mcp = JSON.parse(lines[1])
      expect(mcp["mcp_servers"]).to eq([] of JSON::Any)

      # No warnings should be emitted
      expect(renderer.warnings).to be_empty
    end
  end

  it "includes the config name for known URLs" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
        mcp_servers:
          my_server:
            url: http://localhost:1234
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      session = McpSaveProbeSession.new(renderer, options)
      session.add_mcp_connection(MockMcpConnection.new("http://localhost:1234"))

      io = IO::Memory.new
      session.save_session(io)
      io.rewind

      lines = io.each_line.to_a
      expect(lines.size).to eq(4)

      # Line 2: MCP servers — should contain "my_server"
      mcp = JSON.parse(lines[1])
      expect(mcp["mcp_servers"][0].as_s).to eq("my_server")

      # No warnings should be emitted
      expect(renderer.warnings).to be_empty
    end
  end
end
