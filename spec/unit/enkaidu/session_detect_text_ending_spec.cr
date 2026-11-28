require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Renderer that captures llm_text calls for verifying ending detection.
class DetectTextEndingProbeRenderer < EnkaiduWiretapTestRenderer
  struct LlmTextCall
    getter text : String
    getter reasoning : Bool
    getter starting : Bool
    getter ending : Bool

    def initialize(@text, @reasoning, @starting, @ending); end
  end

  getter llm_text_calls = [] of LlmTextCall

  def llm_text(text, reasoning : Bool, starting : Bool = false, ending : Bool = false) : Nil
    @llm_text_calls << LlmTextCall.new(text.to_s, reasoning, starting, ending)
  end
end

# Probe session that exposes the private detect_text_ending method.
class DetectTextEndingProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end

  def detect_text_ending_public(curr_event_type, prev_event) : Nil
    detect_text_ending(curr_event_type, prev_event)
  end
end

# A mock chat with streaming enabled.
class StreamingMockChatForDetectEnding < MockChat
  def initialize
    super
    @streaming = true
  end
end

Spectator.describe "Enkaidu::Session detect_text_ending" do
  include EnkaiduSessionWiretapHelpers

  def build_session(renderer, streaming = false)
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = DetectTextEndingProbeSession.new(renderer, options)
    mock_chat = streaming ? StreamingMockChatForDetectEnding.new : MockChat.new
    session.set_mock_chat(mock_chat)
    session
  end

  context "non-streaming" do
    it "is a no-op when streaming is false" do
      with_ollama_envs do
        renderer = DetectTextEndingProbeRenderer.new
        session = build_session(renderer)
        prev_event = {type: LLM::Event::Text, content: JSON::Any.new("hello")}
        session.detect_text_ending_public(nil, prev_event)

        expect(renderer.llm_text_calls).to be_empty
      end
    end
  end

  context "streaming, end-of-stream (curr_event_type is nil)" do
    it "emits llm_text ending for prev=Text" do
      with_ollama_envs do
        renderer = DetectTextEndingProbeRenderer.new
        session = build_session(renderer, streaming: true)
        prev_event = {type: LLM::Event::Text, content: JSON::Any.new("final text")}
        session.detect_text_ending_public(nil, prev_event)

        expect(renderer.llm_text_calls.size).to eq(1)
        call = renderer.llm_text_calls.first
        expect(call.text).to eq("")
        expect(call.reasoning).to be_falsey
        expect(call.ending).to be_truthy
      end
    end

    it "emits llm_text ending for prev=ReasoningEvent" do
      with_ollama_envs do
        renderer = DetectTextEndingProbeRenderer.new
        session = build_session(renderer, streaming: true)
        prev_event = {type: LLM::Event::ReasoningEvent, content: JSON::Any.new("final reasoning")}
        session.detect_text_ending_public(nil, prev_event)

        expect(renderer.llm_text_calls.size).to eq(1)
        call = renderer.llm_text_calls.first
        expect(call.text).to eq("")
        expect(call.reasoning).to be_truthy
        expect(call.ending).to be_truthy
      end
    end

    it "does not emit ending for prev=CallingTool" do
      with_ollama_envs do
        renderer = DetectTextEndingProbeRenderer.new
        session = build_session(renderer, streaming: true)
        content = JSON.parse({
          "name"      => "echo",
          "arguments" => %({\"text\":\"hi\"}),
        }.to_json)
        prev_event = {type: LLM::Event::CallingTool, content: content}
        session.detect_text_ending_public(nil, prev_event)

        expect(renderer.llm_text_calls).to be_empty
      end
    end

    it "does not emit ending when prev_event is nil" do
      with_ollama_envs do
        renderer = DetectTextEndingProbeRenderer.new
        session = build_session(renderer, streaming: true)
        session.detect_text_ending_public(nil, nil)

        expect(renderer.llm_text_calls).to be_empty
      end
    end
  end

  context "streaming, same type transition" do
    it "does not emit ending for Text to Text" do
      with_ollama_envs do
        renderer = DetectTextEndingProbeRenderer.new
        session = build_session(renderer, streaming: true)
        prev_event = {type: LLM::Event::Text, content: JSON::Any.new("first")}
        session.detect_text_ending_public(LLM::Event::Text, prev_event)

        expect(renderer.llm_text_calls).to be_empty
      end
    end

    it "does not emit ending for ReasoningEvent to ReasoningEvent" do
      with_ollama_envs do
        renderer = DetectTextEndingProbeRenderer.new
        session = build_session(renderer, streaming: true)
        prev_event = {type: LLM::Event::ReasoningEvent, content: JSON::Any.new("thinking")}
        session.detect_text_ending_public(LLM::Event::ReasoningEvent, prev_event)

        expect(renderer.llm_text_calls).to be_empty
      end
    end
  end
end
