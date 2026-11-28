require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that records `re_ask` invocations (schema + exclude flags) and
# emits a text event followed by a done event.
class ReAskSyncProbeChat < LLM::Chat
  TEXT = "re-asked text"

  getter re_ask_schemas = [] of LLM::ResponseSchema?
  getter re_ask_exclude_reasoning = [] of Bool
  getter re_ask_exclude_skip = [] of Int32
  getter emitted_events = [] of LLM::ChatEvent

  def re_ask(response_schema : LLM::ResponseSchema? = nil,
             exclude_reasoning_in_history = false,
             exclude_reasoning_skip = 0,
             & : LLM::ChatEvent ->) : Nil
    @re_ask_schemas << response_schema
    @re_ask_exclude_reasoning << exclude_reasoning_in_history
    @re_ask_exclude_skip << exclude_reasoning_skip
    text_event : LLM::ChatEvent = {type: LLM::Event::Text, content: JSON::Any.new(TEXT)}
    done_event : LLM::ChatEvent = {type: LLM::Event::Done, content: JSON::Any.new(nil)}
    emitted_events << text_event
    emitted_events << done_event
    yield text_event
    yield done_event
    nil
  end

  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end
end

class ReAskSyncProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end

  # `re_ask_sync` is private on `Enkaidu::Session`; this public wrapper
  # exercises it from the spec without changing the source.
  def call_re_ask_sync(schema : LLM::ResponseSchema? = nil)
    re_ask_sync(response_json_schema: schema)
  end
end

Spectator.describe "Enkaidu::Session re_ask_sync recording" do
  include LLMSpecHelpers

  it "wraps re_ask events in the recorder and forwards the schema to chat.re_ask" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      recorder_io = IO::Memory.new
      options = EnkaiduRecorderTestOptions.new(renderer, recorder_io)
      session = ReAskSyncProbeSession.new(renderer, options)
      mock_chat = ReAskSyncProbeChat.new
      session.set_mock_chat(mock_chat)

      schema = LLM::ResponseSchema.from_json(%({
        "name": "answer",
        "description": "Answer the question.",
        "schema": {"type": "object", "properties": {"ok": {"type": "boolean"}}},
        "strict": true
      }))

      session.call_re_ask_sync(schema)

      # The schema and exclude flags given to `re_ask_sync` reach `chat.re_ask`.
      expect(mock_chat.re_ask_schemas).to eq([schema])
      expect(mock_chat.re_ask_exclude_reasoning).to eq([false])
      expect(mock_chat.re_ask_exclude_skip).to eq([0])

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
      expect(text_event["content"].as_s).to eq(ReAskSyncProbeChat::TEXT)
    end
  end
end