require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Probe renderer that captures llm_text, llm_text_block, and llm_error calls
# which the default EnkaiduWiretapTestRenderer leaves as no-ops.
class ProcessEventProbeRenderer < EnkaiduWiretapTestRenderer
  struct LlmTextCall
    getter text : String
    getter reasoning : Bool
    getter starting : Bool
    getter ending : Bool

    def initialize(@text, @reasoning, @starting, @ending); end
  end

  struct LlmTextBlockCall
    getter text : String
    getter reasoning : Bool

    def initialize(@text, @reasoning); end
  end

  struct LlmErrorCall
    getter event : LLM::ChatEvent
    getter message : String?

    def initialize(@event, @message); end
  end

  getter llm_text_calls = [] of LlmTextCall
  getter llm_text_block_calls = [] of LlmTextBlockCall
  getter llm_error_calls = [] of LlmErrorCall

  def llm_text(text, reasoning : Bool, starting : Bool = false, ending : Bool = false) : Nil
    @llm_text_calls << LlmTextCall.new(text.to_s, reasoning, starting, ending)
  end

  def llm_text_block(text, reasoning : Bool) : Nil
    @llm_text_block_calls << LlmTextBlockCall.new(text.to_s, reasoning)
  end

  def llm_error(err, message : String? = nil) : Nil
    event = case err
            when LLM::ChatEvent then err
            else {type: LLM::Event::Done, content: JSON::Any.new(nil)}
            end
    @llm_error_calls << LlmErrorCall.new(event, message)
  end
end

# Probe session that exposes the protected process_event method.
class ProcessEventProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end

  def process_event_public(event, prev_event, & : LLM::FunctionCall ->) : Nil
    process_event(event, prev_event) do |fc|
      yield fc
    end
  end
end

# A mock chat with streaming enabled for testing the streaming code path.
class StreamingMockChat < MockChat
  def initialize
    super
    @streaming = true
  end
end
Spectator.describe "Enkaidu::Session process_event" do
  include EnkaiduSessionWiretapHelpers

  def build_session(renderer, streaming = false)
    options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
    session = ProcessEventProbeSession.new(renderer, options)
    mock_chat = streaming ? StreamingMockChat.new : MockChat.new
    session.set_mock_chat(mock_chat)
    session
  end

  context "non-streaming" do
    it "renders Text events via llm_text_block with reasoning: false" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer)
        event = {type: LLM::Event::Text, content: JSON::Any.new("hello")}
        session.process_event_public(event, nil) { }

        expect(renderer.llm_text_block_calls.size).to eq(1)
        expect(renderer.llm_text_block_calls.first.text).to eq("hello")
        expect(renderer.llm_text_block_calls.first.reasoning).to be_falsey
      end
    end

    it "renders ReasoningEvent via llm_text_block with reasoning: true" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer)
        event = {type: LLM::Event::ReasoningEvent, content: JSON::Any.new("thinking...")}
        session.process_event_public(event, nil) { }

        expect(renderer.llm_text_block_calls.size).to eq(1)
        expect(renderer.llm_text_block_calls.first.text).to eq("thinking...")
        expect(renderer.llm_text_block_calls.first.reasoning).to be_truthy
      end
    end

    it "yields the function call for ToolCallRequested events" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer)
        content = JSON.parse({
          "id"        => "call_1",
          "name"      => "echo",
          "arguments" => %({"text":"hi"}),
        }.to_json)
        event = {type: LLM::Event::ToolCallRequested, content: content}

        yielded = nil
        session.process_event_public(event, nil) { |fc| yielded = fc }

        expect(yielded).not_to be_nil
        expect(yielded.not_nil!.name).to eq("echo")
        expect(yielded.not_nil!.id).to eq("call_1")
      end
    end

    it "renders CallingTool events via llm_tool_call" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer)
        content = JSON.parse({
          "name"      => "echo",
          "arguments" => %({"text":"hi"}),
        }.to_json)
        event = {type: LLM::Event::CallingTool, content: content}
        session.process_event_public(event, nil) { }

        expect(renderer.tool_calls).to eq(["echo"])
      end
    end

    it "renders WarnTooManyRequestsDelay via warning_with" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer)
        event = {type: LLM::Event::WarnTooManyRequestsDelay, content: JSON::Any.new("rate limited")}
        session.process_event_public(event, nil) { }

        expect(renderer.warnings.size).to eq(1)
        expect(renderer.warnings.first.includes?("Too many requests")).to be_truthy
      end
    end

    it "renders WarnUnknownToolCall via llm_error with not-installed message" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer)
        content = JSON.parse({
          "name" => "nonexistent_tool",
        }.to_json)
        event = {type: LLM::Event::WarnUnknownToolCall, content: content}
        session.process_event_public(event, nil) { }

        expect(renderer.llm_error_calls.size).to eq(1)
        expect(renderer.llm_error_calls.first.message).to eq("The tool `nonexistent_tool` is not installed.")
      end
    end

    it "renders other warn events (WarnUnexpected) via llm_error without message" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer)
        event = {type: LLM::Event::WarnUnexpected, content: JSON::Any.new("something odd")}
        session.process_event_public(event, nil) { }

        expect(renderer.llm_error_calls.size).to eq(1)
        expect(renderer.llm_error_calls.first.message).to be_nil
      end
    end
  end

  context "streaming" do
    it "renders Text events via llm_text with reasoning: false" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer, streaming: true)
        event = {type: LLM::Event::Text, content: JSON::Any.new("hello")}
        session.process_event_public(event, nil) { }

        expect(renderer.llm_text_calls.size).to eq(1)
        expect(renderer.llm_text_calls.first.text).to eq("hello")
        expect(renderer.llm_text_calls.first.reasoning).to be_falsey
        expect(renderer.llm_text_calls.first.starting).to be_truthy
      end
    end

    it "fires detect_text_ending when transitioning from Text to ReasoningEvent" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer, streaming: true)
        prev_event = {type: LLM::Event::Text, content: JSON::Any.new("first chunk")}
        event = {type: LLM::Event::ReasoningEvent, content: JSON::Any.new("thinking")}
        session.process_event_public(event, prev_event) { }

        # detect_text_ending should emit an ending for the previous Text type
        ending_call = renderer.llm_text_calls.find do |c|
          c.ending && !c.reasoning
        end
        expect(ending_call).not_to be_nil
        expect(ending_call.not_nil!.text).to eq("")
        expect(ending_call.not_nil!.ending).to be_truthy

        # Then the actual reasoning event is rendered with starting: true
        reasoning_call = renderer.llm_text_calls.find do |c|
          c.reasoning && !c.ending
        end
        expect(reasoning_call).not_to be_nil
        expect(reasoning_call.not_nil!.text).to eq("thinking")
        expect(reasoning_call.not_nil!.starting).to be_truthy
      end
    end

    it "fires detect_text_ending when transitioning from ReasoningEvent to Text" do
      with_ollama_envs do
        renderer = ProcessEventProbeRenderer.new
        session = build_session(renderer, streaming: true)
        prev_event = {type: LLM::Event::ReasoningEvent, content: JSON::Any.new("thought")}
        event = {type: LLM::Event::Text, content: JSON::Any.new("response")}
        session.process_event_public(event, prev_event) { }

        # detect_text_ending should emit an ending for the previous ReasoningEvent
        ending_call = renderer.llm_text_calls.find do |c|
          c.ending && c.reasoning
        end
        expect(ending_call).not_to be_nil
        expect(ending_call.not_nil!.text).to eq("")
        expect(ending_call.not_nil!.ending).to be_truthy

        # Then the actual Text event is rendered with starting: true
        text_call = renderer.llm_text_calls.find do |c|
          !c.reasoning && !c.ending
        end
        expect(text_call).not_to be_nil
        expect(text_call.not_nil!.text).to eq("response")
        expect(text_call.not_nil!.starting).to be_truthy
      end
    end
  end
end
