require "../../spec_helper"
require "json"

# Exercises the tool-call round-trip: `ask` (the model requests a tool),
# `call_tools_and_setup_ask` (runs the tool and appends the result to history),
# and `re_ask` (hands the result back for a final answer). This is the core
# path the `call_tools_and_setup_ask` boundary refactor must preserve.
#
# Wiretap records the two interactions (the initial ask and the follow-up
# re_ask) in one transcript and replays them offline afterwards.
Spectator.describe LLM::Protocol::ChatCompletions::Chat do
  include LLMSpecHelpers

  describe "tool-call round-trip" do
    it "runs a requested tool and returns a final answer" do
      chat = build_ollama_chat
      chat.with_tool TestEchoTool.new

      first_events = uninitialized Array(LLM::ChatEvent)
      tool_events  = [] of LLM::ChatEvent
      final_events = uninitialized Array(LLM::ChatEvent)
      Wiretap.intercept("ollama_tool_call") do
        # First ask: the model should request the `echo` tool.
        first_events = ask_events(chat, "Please echo the word hello using the echo tool. Do not answer in plain text.")

        # It requested a tool call for `echo`.
        call_event = first_events.find { |e| e["type"] == "tool_call_requested" }
        expect(call_event).not_to be_nil
        expect(call_event.not_nil!["content"].dig("function", "name").as_s).to eq("echo")

        # Run the requested tool (returns the number of calls made).
        ncalls = chat.call_tools_and_setup_ask([call_event.not_nil!["content"]]) do |ev|
          tool_events << ev
        end
        expect(ncalls).to eq(1)
        expect(tool_events.any? { |e| e["type"] == "calling_tool" }).to be_true

        # Hand the tool result back and get the final answer.
        final_events = re_ask_events(chat)
      end

      expect(reply_text(final_events)).not_to be_empty
    end
  end
end
