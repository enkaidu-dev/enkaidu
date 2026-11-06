require "../../spec_helper"
require "json"

Spectator.describe LLM::Protocol::Responses::Chat do
  include LLMSpecHelpers

  it "parallel reproduction" do
    chat = build_ollama_chat(LLM::ProtocolKind::Responses)
    chat.with_tool TestEchoTool.new
    first_events = uninitialized Array(LLM::ChatEvent)
    tool_events = [] of LLM::ChatEvent
    final_events = uninitialized Array(LLM::ChatEvent)
    Wiretap.intercept("repro_parallel_responses") do
      first_events = ask_events(chat, "Echo the word hello and then echo the word world using the echo tool. Do not answer in plain text.")
      call_events = first_events.select { |e| e["type"].tool_call_requested? }
      expect(call_events.size).to be >= 1
      ncalls = chat.call_tools_and_setup_ask(call_events.map { |e| LLM::FunctionCall.from_json(e["content"]) }) do |ev|
        tool_events << ev
      end
      expect(ncalls).to be >= 1
      final_events = re_ask_events(chat)
    end
    # puts "FINAL REPLY=#{reply_text(final_events)[0, 100].inspect}"
    # puts "FIRST CALL COUNT=#{first_events.select { |e| e["type"].tool_call_requested? }.size}"
  end
end
