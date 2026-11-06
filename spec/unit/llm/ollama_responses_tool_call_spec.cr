require "../../spec_helper"
require "json"

# Exercises the tool-call round-trip for the Responses protocol: `ask`, the
# model requests a tool, `call_tools_and_setup_ask`, and `re_ask`.
#
# Wiretap records/replays interactions against `/v1/responses`. Recorded
# transcripts for this path are not currently present in the repository.
Spectator.describe LLM::Protocol::Responses::Chat do
  include LLMSpecHelpers

  describe "tool-call round-trip" do
    it "runs a requested tool and returns a final answer" do
      [true, false].each do |streaming|
        chat = build_ollama_chat(LLM::ProtocolKind::Responses)
        chat.with_tool TestEchoTool.new
        chat.with_streaming if streaming == true
        first_events = uninitialized Array(LLM::ChatEvent)
        tool_events = [] of LLM::ChatEvent
        final_events = uninitialized Array(LLM::ChatEvent)
        Wiretap.intercept(streaming ? "ollama_responses_streaming_tool_call" : "ollama_responses_tool_call") do
          first_events = ask_events(chat, "Please echo the word hello using the echo tool. Do not answer in plain text.")

          call_event = first_events.find { |e| e["type"].tool_call_requested? }
          expect(call_event).not_to be_nil
          expect(call_event.not_nil!["content"].dig("name").as_s).to eq("echo")

          ncalls = chat.call_tools_and_setup_ask([LLM::FunctionCall.from_json(call_event.not_nil!["content"])]) do |ev|
            tool_events << ev
          end
          expect(ncalls).to eq(1)
          expect(tool_events.any? { |e| e["type"].calling_tool? }).to be_true

          final_events = re_ask_events(chat)
        end
        expect(reply_text(final_events)).not_to be_empty
      end
    end
  end
end
