require "../../spec_helper"
require "json"

Spectator.describe "LLM tool calls with malformed arguments" do
  include LLMSpecHelpers

  it "appends a matching error output and continues the loop for both protocols" do
    [LLM::ProtocolKind::ChatCompletions, LLM::ProtocolKind::Responses].each do |protocol|
      chat = build_ollama_chat(protocol)
      chat.with_tool(TestEchoTool.new)
      chat.append_message(LLM::Message::MultiContent.new(prompt: "Run the echo tool."))

      calls = [
        LLM::FunctionCall.new("call_valid", "echo", %q|{"value":"hello"}|),
        LLM::FunctionCall.new("call_invalid", "echo", %q|{"value":}|),
      ]
      calling_events = [] of LLM::ChatEvent

      count = chat.call_tools_and_setup_ask(calls) do |event|
        calling_events << event if event[:type].calling_tool?
      end

      expect(count).to eq(2)
      expect(calling_events.size).to eq(2)

      history = JSON.parse(save_chat_json(chat))
      outputs = history["messages"].as_a.compact_map do |wrapped|
        message = wrapped["message"]?
        next unless message && message["role"]?.try(&.as_s?) == "tool"
        {message["tool_call_id"].as_s, message["content"].as_s}
      end

      expect(outputs.size).to eq(2)
      expect(outputs[0][0]).to eq("call_valid")
      expect(outputs[0][1]).to eq(%({"echoed":"hello"}))
      expect(outputs[1][0]).to eq("call_invalid")
      error = JSON.parse(outputs[1][1])
      expect(error["error"].as_s).to contain("Invalid JSON arguments")
      expect(error["instruction"].as_s).to contain("valid JSON")
    end
  end
end
