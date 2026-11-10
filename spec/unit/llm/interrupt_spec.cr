require "../../spec_helper"
require "json"

Spectator.describe LLM::Chat do
  include LLMSpecHelpers

  describe "#interrupt_and_rollback" do
    it "rolls back history to before the current user turn" do
      chat = build_ollama_chat(LLM::ProtocolKind::ChatCompletions)
      
      # Turn 1: Completed
      chat.append_message(LLM::Message::MultiContent.new("First question"))
      chat.append_message(LLM::Message::Response.new("First answer", reasoning: nil))
      
      # Turn 2: Interrupted mid-turn (prompt added, response missing)
      chat.append_message(LLM::Message::MultiContent.new("Second question"))
      
      success = chat.interrupt_and_rollback
      expect(success).to be_true

      # Should leave only Turn 1 in history
      conversations = chat.extract_conversations(LLM::Conversation::SessionFull)
      expect(conversations).not_to be_nil
      if conv_json = conversations
        parsed = JSON.parse(conv_json).as_a
        expect(parsed.size).to eq(2)
        expect(parsed[0]["role"].as_s).to eq("user")
        expect(parsed[1]["role"].as_s).to eq("assistant")
        expect(parsed[1]["content"].as_s).to eq("First answer")
      end
    end

    it "returns false when history is empty" do
      chat = build_ollama_chat(LLM::ProtocolKind::ChatCompletions)
      expect(chat.interrupt_and_rollback).to be_false
    end
  end

  describe "#interrupt_and_cleanup" do
    it "synthesizes missing tool calls and appends final assistant response" do
      chat = build_ollama_chat(LLM::ProtocolKind::ChatCompletions)
      
      chat.append_message(LLM::Message::MultiContent.new("Run tools"))
      
      # Assistant requested 2 tool calls
      tool_calls_json = [
        JSON.parse({"id" => "call_1", "function" => {"name" => "tool_a", "arguments" => "{}"}}.to_json),
        JSON.parse({"id" => "call_2", "function" => {"name" => "tool_b", "arguments" => "{}"}}.to_json),
      ]
      chat.append_message(LLM::Message::Response.new("I will call two tools", reasoning: nil, tool_calls: tool_calls_json))
      
      # Only tool_1 finished before interrupt
      chat.append_message(LLM::Message::ToolCall.new("call_1", "tool_a", "Tool 1 result"))

      # Perform interrupt cleanup
      success = chat.interrupt_and_cleanup(
        tool_cancel_message: "Cancelled by user",
        final_response: "[Turn interrupted]"
      )
      expect(success).to be_true

      conversations = chat.extract_conversations(LLM::Conversation::SessionFull)
      expect(conversations).not_to be_nil
      if conv_json = conversations
        parsed = JSON.parse(conv_json).as_a
        # Expected messages:
        # 0: user "Run tools"
        # 1: assistant "I will call two tools"
        # 2: tool "call_1"
        # 3: tool "call_2" (synthesized)
        # 4: assistant "[Turn interrupted]" (synthesized)
        expect(parsed.size).to eq(5)

        # Verify synthesized tool call (index 3)
        expect(parsed[3]["role"].as_s).to eq("tool")
        expect(parsed[3]["tool_call_id"].as_s).to eq("call_2")
        expect(parsed[3]["content"].as_s).to eq("Cancelled by user")

        # Verify final assistant response (index 4)
        expect(parsed[4]["role"].as_s).to eq("assistant")
        expect(parsed[4]["content"].as_s).to eq("[Turn interrupted]")
      end
    end

    it "appends final response if interrupted during simple prompt streaming" do
      chat = build_ollama_chat(LLM::ProtocolKind::ChatCompletions)
      chat.append_message(LLM::Message::MultiContent.new("Hello"))

      chat.interrupt_and_cleanup(final_response: "[Interrupted]")

      conversations = chat.extract_conversations(LLM::Conversation::SessionFull)
      expect(conversations).not_to be_nil
      if conv_json = conversations
        parsed = JSON.parse(conv_json).as_a
        expect(parsed.size).to eq(2)
        expect(parsed[1]["role"].as_s).to eq("assistant")
        expect(parsed[1]["content"].as_s).to eq("[Interrupted]")
      end
    end
  end
end
