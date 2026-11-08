require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class EnkaiduForkProbeSession < EnkaiduWiretapTestSession
  def tool_count : Int32
    count = 0
    chat.each_tool { count += 1 }
    count
  end

  def chat_snapshot : String
    io = IO::Memory.new
    chat.save(io)
    io.rewind
    io.gets_to_end
  end

  def opts_id : UInt64
    @opts.object_id
  end

  def connection_id : UInt64
    @connection.object_id
  end
end

Spectator.describe "Enkaidu::Session fork" do
  include EnkaiduSessionWiretapHelpers

  it "fork with all retention copies state" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = EnkaiduForkProbeSession.new(renderer, options)

      tool = Tools::DateAndTime::GetCurrentDatetimeTool.new(renderer)
      base.install_tool(tool)

      forked = EnkaiduForkProbeSession.new(base)

      expect(forked.parent).to be base
      expect(forked.sub_agent?).to be_false
      expect(forked.renderer).to be renderer
      expect(forked.opts_id).to eq(base.opts_id)
      expect(forked.connection_id).to eq(base.connection_id)
      expect(forked.unique_model_name).to eq(base.unique_model_name)
      expect(forked.tool_count).to eq(base.tool_count)
      expect(forked.chat_snapshot).to eq(base.chat_snapshot)
    end
  end
end
