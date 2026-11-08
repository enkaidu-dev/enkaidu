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

  def mcp_functions
    super
  end

  def mcp_connections
    super
  end

  def loaded_toolsets
    super
  end

  def mcp_prompts_count : Int32
    mcp_prompts.size
  end

  def config_prompts_count : Int32
    config_prompts.size
  end

  def prompts_by_name_count : Int32
    prompts_by_name.size
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

  it "fork with keep_tools = false does not copy tools" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = EnkaiduForkProbeSession.new(renderer, options)

      base.install_tool(Tools::DateAndTime::GetCurrentDatetimeTool.new(renderer))

      forked = EnkaiduForkProbeSession.new(base, false)

      expect(forked.parent).to be base
      expect(forked.tool_count).to eq(0)
      expect(forked.mcp_functions.size).to eq(0)
      expect(forked.mcp_connections.size).to eq(0)
      expect(forked.loaded_toolsets.size).to eq(0)
    end
  end

  it "fork with keep_prompts = false does not copy prompts" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      yaml = <<-YAML
      prompts:
        helper:
          template: "hi"
          description: "helper prompt"
      YAML
      options = EnkaiduUniqueModelTestOptions.new(renderer, yaml)
      base = EnkaiduForkProbeSession.new(renderer, options)
      base.auto_load

      forked = EnkaiduForkProbeSession.new(base, true, false)

      expect(forked.mcp_prompts_count).to eq(0)
      expect(forked.config_prompts_count).to eq(0)
      expect(forked.prompts_by_name_count).to eq(0)
    end
  end

  it "fork with keep_history = false leaves session empty" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = EnkaiduForkProbeSession.new(renderer, options)

      Wiretap.intercept("ollama_ask_non_streaming") do
        base.ask_sync("Hello")
      end

      forked = EnkaiduForkProbeSession.new(base, true, true, false)
      fresh = EnkaiduForkProbeSession.new(renderer, options)

      expect(forked.chat_snapshot).to_not eq(base.chat_snapshot)
      expect(forked.chat_snapshot).to eq(fresh.chat_snapshot)
    end
  end

  it "fork with sub_agent = true sets sub_agent and accumulates depth" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      base = EnkaiduForkProbeSession.new(renderer, options)

      sub = EnkaiduForkProbeSession.new(base, true, true, true, nil, true, true)

      expect(sub.sub_agent?).to be_true
      expect(sub.parent).to be base
      expect(sub.sub_agent_depth).to eq(1)

      nested = EnkaiduForkProbeSession.new(sub, true, true, true, nil, true, true)

      expect(nested.sub_agent_depth).to eq(2)
    end
  end
end
