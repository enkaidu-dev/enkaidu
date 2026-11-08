require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Subclass exposing internal state for testing
class EnkaiduForkProbeSession < EnkaiduWiretapTestSession
  def chat_snapshot : String
    io = IO::Memory.new
    chat.save(io)
    io.rewind
    io.gets_to_end
  end

  def chat_snapshot_size : Int32
    chat_snapshot.size
  end
end

Spectator.describe "Enkaidu::Session fork with exclude_last_turn" do
  include EnkaiduSessionWiretapHelpers

  it "fork with exclude_last_turn drops the most recent turn" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      parent = EnkaiduForkProbeSession.new(renderer, options)

      # Add two turns using a safe, non-recording Wiretap intercept
      prev_mode = Wiretap.config.record_mode
      Wiretap.configure { |c| c.record_mode = :none }
      Wiretap.intercept(LLMSpecHelpers::NON_STREAMING_ASK_TRANSCRIPT) { parent.ask_sync("First prompt") }
      Wiretap.intercept(LLMSpecHelpers::NON_STREAMING_ASK_TRANSCRIPT) { parent.ask_sync("Second prompt") }
      Wiretap.configure { |c| c.record_mode = prev_mode }


      # Ensure parent has more content than the forked one (checked later)

      # Fork excluding the last turn
      forked = EnkaiduForkProbeSession.new(parent, true, true, true, nil, true)

      expect(forked.parent).to be parent
      expect(forked.sub_agent?).to be_false
      expect(parent.chat_snapshot_size).to be > forked.chat_snapshot_size
      # Ensure the forked session does not contain the second turn
      expect(forked.chat_snapshot).not_to eq(parent.chat_snapshot)
    end
  end
end
