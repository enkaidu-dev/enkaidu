require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that emits a text event followed by a done event from `ask`.
class AskSyncRecordingProbeChat < LLM::Chat
  TEXT = "recorded text"

  getter emitted_events = [] of LLM::ChatEvent

  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
    text_event : LLM::ChatEvent = {type: LLM::Event::Text, content: JSON::Any.new(TEXT)}
    done_event : LLM::ChatEvent = {type: LLM::Event::Done, content: JSON::Any.new(nil)}
    emitted_events << text_event
    emitted_events << done_event
    yield text_event
    yield done_event
    nil
  end
end

class AskSyncRecordingProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session ask_sync recording" do
  include LLMSpecHelpers

  it "writes '[' , one JSON line per event, and ']' to the recorder" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      recorder_io = IO::Memory.new
      options = EnkaiduRecorderTestOptions.new(renderer, recorder_io)
      session = AskSyncRecordingProbeSession.new(renderer, options)
      mock_chat = AskSyncRecordingProbeChat.new
      session.set_mock_chat(mock_chat)

      session.ask_sync(query: "record me")

      # The mock chat emitted exactly the events the recorder should capture.
      expect(mock_chat.emitted_events.map { |e| e["type"] }).to eq(
        [LLM::Event::Text, LLM::Event::Done])

      recorder_io.rewind
      lines = recorder_io.each_line.to_a

      # Ignore blank lines; the recorder may also emit "," separator lines
      # between event JSON lines when multiple events are recorded.
      significant = lines.reject { |line| line.strip.empty? }
      expect(significant.first).to eq("[")
      expect(significant.last).to eq("]")

      json_lines = significant.reject { |line| line.strip == "[" || line.strip == "]" || line.strip == "," }
      events = json_lines.map { |line| JSON.parse(line) }

      # Recorded enum names are lowercased by JSON serialization.
      expect(events.size).to eq(2)
      expect(events.map { |e| e["type"].as_s }).to eq(
        [LLM::Event::Text.to_s.downcase, LLM::Event::Done.to_s.downcase])

      text_event = events.find { |e| e["type"].as_s == LLM::Event::Text.to_s.downcase }.not_nil!
      expect(text_event["content"].as_s).to eq(AskSyncRecordingProbeChat::TEXT)

      # Multiple events are comma-separated in the recording.
      expect(significant).to contain(",")
    end
  end
end