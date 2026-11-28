require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class SaveSessionProbeSession < EnkaiduWiretapTestSession
  def chat : LLM::Chat
    @chat
  end
end

Spectator.describe "Enkaidu::Session save_session" do
  include EnkaiduSessionWiretapHelpers

  def new_session
    renderer = EnkaiduWiretapTestRenderer.new
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = SaveSessionProbeSession.new(renderer, options)
    {session, renderer}
  end

  it "writes exactly 4 lines for a fresh session" do
    with_ollama_envs do
      session, _ = new_session

      io = IO::Memory.new
      session.save_session(io)
      io.rewind

      lines = io.each_line.to_a

      expect(lines.size).to eq(4)

      # Line 1: About JSON
      about = JSON.parse(lines[0])
      expect(about["app"]).to eq("Enkaidu")
      expect(about["ver"]).not_to be_nil

      # Line 2: MCP servers (empty for fresh session)
      mcp = JSON.parse(lines[1])
      expect(mcp["mcp_servers"]).to eq([] of JSON::Any)

      # Line 3: Toolsets (empty for fresh session)
      toolsets = JSON.parse(lines[2])
      expect(toolsets["toolsets"]).to eq([] of JSON::Any)

      # Line 4: Chat history (valid JSON with format and messages keys)
      history = JSON.parse(lines[3])
      expect(history["format"]).to eq("LLM::History")
      expect(history["messages"]).to eq([] of JSON::Any)
    end
  end

  it "includes chat history messages in the saved output" do
    with_ollama_envs do
      session, _ = new_session

      # Add a user message to the chat history before saving
      session.chat.append_message(LLM::Message::MultiContent.new("hello world"))

      io = IO::Memory.new
      session.save_session(io)
      io.rewind

      lines = io.each_line.to_a

      expect(lines.size).to eq(4)

      # Verify the history line contains the message we added
      history = JSON.parse(lines[3])
      messages = history["messages"].as(JSON::Any)
      expect(messages.size).to eq(1)
      first_msg = messages[0]
      expect(first_msg["message"]["role"]).to eq("user")
      expect(first_msg["message"]["content"][0]["type"]).to eq("text")
      expect(first_msg["message"]["content"][0]["text"]).to eq("hello world")
    end
  end
end
