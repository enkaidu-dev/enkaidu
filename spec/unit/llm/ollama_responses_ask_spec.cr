require "../../spec_helper"
require "json"

# End-to-end check of the Responses adapter against the local Ollama instance,
# which serves both `/v1/responses` and `/v1/chat/completions`. The chat is
# built through the usual Ollama provider with `OLLAMA_ADAPTER=responses` set,
# so the Responses adapter (not the default ChatCompletions one) owns the
# request. Wiretap records the interaction on the first run and replays it
# afterwards, so the suite is stable and runs offline once recorded.
Spectator.describe LLM::Protocol::Responses::Chat do
  include LLMSpecHelpers

  describe "#ask (non-streaming, Responses wire)" do
    it "posts to /v1/responses using the Responses request shape" do
      chat = build_ollama_chat(LLM::ProtocolKind::Responses)
      events = uninitialized Array(LLM::ChatEvent)
      Wiretap.intercept("ollama_responses_ask_non_streaming") do
        events = ask_events(chat, POPULATE_PROMPT)
      end

      # A non-empty reply was emitted through the canonical `text` events.
      expect(reply_text(events)).not_to be_empty

      # The recorded request is a Responses call: `input` (not `messages`),
      # ending in the user's prompt as an `input_text` part.
      body = recorded_request_body("ollama_responses_ask_non_streaming")
      expect(body["model"].as_s).to eq(LLMSpecHelpers::MODEL)
      expect(body["stream"]).to eq(false)
      expect(body.as_h.has_key?("messages")).to be_false
      input = body["input"].as_a
      last = input.last.not_nil!
      expect(last["type"].as_s).to eq("message")
      expect(last["role"].as_s).to eq("user")
      expect(last.dig("content", 0, "type").as_s).to eq("input_text")
      expect(last.dig("content", 0, "text").as_s).to eq(POPULATE_PROMPT)
    end
  end

  describe "#ask (streaming, Responses SSE)" do
    it "streams the reply and completes with a done marker" do
      chat = build_ollama_chat(LLM::ProtocolKind::Responses)
      chat.with_streaming
      events = uninitialized Array(LLM::ChatEvent)
      Wiretap.intercept("ollama_responses_ask_streaming") do
        events = ask_events(chat, POPULATE_PROMPT)
      end

      # The reply is assembled from streamed text deltas and is non-empty.
      expect(reply_text(events)).not_to be_empty
      # The stream completed with a `done` marker.
      expect(events.any? { |e| e["type"].done? }).to be_true

      # The recorded request asked for streaming on the Responses wire.
      body = recorded_request_body("ollama_responses_ask_streaming")
      expect(body["stream"]).to eq(true)
      expect(body.as_h.has_key?("messages")).to be_false
    end
  end
end
