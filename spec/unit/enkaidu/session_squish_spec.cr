require "../../spec_helper"
require "../../support/enkaidu_session_helpers"
require "json"

# A session subclass that exposes the chat for loading pre-built histories.
class SquishProbeSession < EnkaiduWiretapTestSession
  def load_history(json : String) : Nil
    chat.load(json)
  end
end

# Build a 2-turn history JSON where turn 0 has no tool calls and
# turn 1 includes a tool call round-trip, so squishing actually
# removes intermediate messages.
def two_turn_history_json : String
  history = LLM::History.new
  # Turn 0: simple user/assistant
  history.append_message(LLM::Message::MultiContent.new("First prompt"))
  history.append_message(LLM::Message::Response.new("First response", nil))
  # Turn 1: user prompt, assistant requests tool, tool result, final response
  history.append_message(LLM::Message::MultiContent.new("Second prompt"))
  tool_calls = [
    JSON.parse({"id" => "call_1", "function" => {"name" => "echo", "arguments" => "{}"}}.to_json),
  ]
  history.append_message(LLM::Message::Response.new(nil, nil, tool_calls))
  history.append_message(LLM::Message::ToolCall.new("call_1", "echo", "tool result"))
  history.append_message(LLM::Message::Response.new("Final response", nil))

  io = IO::Memory.new
  history.to_json(io)
  io.rewind
  io.gets_to_end
end

Spectator.describe "Enkaidu::Session#squish_history" do
  include EnkaiduSessionWiretapHelpers

  def new_session
    renderer = EnkaiduWiretapTestRenderer.new
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = SquishProbeSession.new(renderer, options)
    {session, renderer}
  end

  it "squishes all turns when exclude_past_turns is 0" do
    with_ollama_envs do
      session, renderer = new_session
      session.load_history(two_turn_history_json)

      count = session.squish_history(0)

      # Original: 6 messages. Squished: 4 (MultiContent, Response, MultiContent, Response).
      # The intermediate Response(tool_calls) and ToolCall are dropped;
      # the final Response is appended after the loop.
      expect(count).to eq(2)
      expect(renderer.errors).to be_empty
    end
  end

  it "preserves the last turn when exclude_past_turns is 1" do
    with_ollama_envs do
      session, renderer = new_session
      session.load_history(two_turn_history_json)

      count = session.squish_history(1)

      # Turn 0 squished: simple user/assistant pair (2 msgs, no tool calls to drop).
      # Turn 1 preserved entirely (4 msgs). Total: 6 -> 6, removed: 0.
      expect(count).to eq(0)
      expect(renderer.errors).to be_empty
    end
  end

  it "removes nothing when exclude_past_turns exceeds total turns" do
    with_ollama_envs do
      session, renderer = new_session
      session.load_history(two_turn_history_json)

      count = session.squish_history(99)

      expect(count).to eq(0)
      expect(renderer.errors).to be_empty
    end
  end
end

Spectator.describe "CommandParser for /session x-squish" do
  it "parses /session x-squish with no params" do
    cmd = CommandParser.new("/session x-squish")
    expect(cmd.expect?("/session", "x-squish", exclude_past_turns: String?)).to be_true
  end

  it "parses /session x-squish with exclude_past_turns named arg" do
    cmd = CommandParser.new("/session x-squish exclude_past_turns=2")
    expect(cmd.expect?("/session", "x-squish", exclude_past_turns: String?)).to be_true
    expect(cmd.arg_named?("exclude_past_turns")).to eq("2")
  end
end
