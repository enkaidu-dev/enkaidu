require "../../spec_helper"
require "json"

# Exercises `LLM::Chat#ask` against the local Ollama backend through the
# Chat Completions protocol. Wiretap records the request/response on the
# first run and replays it afterwards, so the assertions are stable and the
# suite runs offline once recorded.
Spectator.describe LLM::Protocol::ChatCompletions::Chat do
  include LLMSpecHelpers

  describe "#ask (non-streaming)" do
    it "sends a chat/completions request and yields the reply text and usage" do
      chat   = build_ollama_chat
      events = uninitialized Array(LLM::ChatEvent)
      Wiretap.intercept("ollama_ask_non_streaming") do
        events = ask_events(chat, "Say hello, world. Reply in one short sentence.")
      end

      # A non-empty reply was emitted and a usage event was reported.
      expect(reply_text(events)).not_to be_empty
      expect(events.any? { |e| e["type"] == "usage" }).to be_true

      # The recorded request is a chat/completions call using our model,
      # non-streaming, ending in the user's prompt.
      body = recorded_request_body("ollama_ask_non_streaming")
      expect(body["model"].as_s).to eq(LLMSpecHelpers::MODEL)
      expect(body["stream"]).to eq(false)
      messages = body["messages"].as_a
      expect(messages.last.not_nil!["role"].as_s).to eq("user")
    end
  end

  describe "#ask (streaming)" do
    it "streams the reply via SSE and reports usage and a done marker" do
      chat = build_ollama_chat
      chat.with_streaming
      events = uninitialized Array(LLM::ChatEvent)
      Wiretap.intercept("ollama_ask_streaming") do
        events = ask_events(chat, "Say hello, world. Reply in one short sentence.")
      end

      # The reply is assembled from streamed text deltas and is non-empty.
      expect(reply_text(events)).not_to be_empty
      # The stream completed with a `done` marker.
      expect(events.any? { |e| e["type"] == "done" }).to be_true
      # The streamed usage chunk is parsed and stored on the chat. (Note the
      # streaming path captures usage onto the response rather than forwarding
      # a `usage` event to the caller, unlike the non-streaming path.)
      expect(chat.usage).not_to be_nil
      expect(chat.usage.not_nil!.total_tokens > 0).to be_true

      # The recorded request asked for streaming.
      body = recorded_request_body("ollama_ask_streaming")
      expect(body["stream"]).to eq(true)
    end
  end
end
