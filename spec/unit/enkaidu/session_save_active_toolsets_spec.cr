require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class SaveActiveToolsetsProbeSession < EnkaiduWiretapTestSession
  def chat : LLM::Chat
    @chat
  end
end

Spectator.describe "Enkaidu::Session save_active_toolsets" do
  include EnkaiduSessionWiretapHelpers

  def new_session
    renderer = EnkaiduWiretapTestRenderer.new
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = SaveActiveToolsetsProbeSession.new(renderer, options)
    {session, renderer}
  end

  def save_and_get_toolsets(session)
    io = IO::Memory.new
    session.save_session(io)
    io.rewind
    lines = io.each_line.to_a
    JSON.parse(lines[2])["toolsets"].as(JSON::Any)
  end

  it "records select when only a subset of tools are active" do
    with_ollama_envs do
      session, _ = new_session

      session.load_toolset_by("FileManagement", ["search", "find"])

      toolsets = save_and_get_toolsets(session)

      expect(toolsets.size).to eq(1)
      entry = toolsets[0]
      expect(entry["name"]).to eq("FileManagement")
      expect(entry["select"]?).not_to be_nil
      selected = entry["select"].as_a
      expect(selected.size).to eq(2)
      expect(selected.to_a.map(&.as_s).sort).to eq(["find", "search"])
    end
  end

  it "omits select key when all tools in the toolset are active" do
    with_ollama_envs do
      session, _ = new_session

      session.load_toolset_by("FileManagement")

      toolsets = save_and_get_toolsets(session)

      expect(toolsets.size).to eq(1)
      entry = toolsets[0]
      expect(entry["name"]).to eq("FileManagement")
      expect(entry["select"]?).to be_nil
    end
  end

  it "records an empty toolsets array when no toolsets are loaded" do
    with_ollama_envs do
      session, _ = new_session

      toolsets = save_and_get_toolsets(session)

      expect(toolsets).to eq([] of JSON::Any)
    end
  end
end
