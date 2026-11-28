require "../../spec_helper"
require "json"

Spectator.describe LLM::History do
  describe "#squish_turns" do
    # Build a 2-turn history where turn 1 includes tool calls.
    # Turn 0: MultiContent("First prompt") -> Response("First response")
    # Turn 1: MultiContent("Second prompt") -> Response(tool_calls) -> ToolCall -> Response("Final response")
    private def build_two_turn_history_with_tools : LLM::History
      history = LLM::History.new
      history.append_message(LLM::Message::MultiContent.new("First prompt"))
      history.append_message(LLM::Message::Response.new("First response", nil))
      history.append_message(LLM::Message::MultiContent.new("Second prompt"))
      tool_calls_json = [
        JSON.parse({"id" => "call_1", "function" => {"name" => "echo", "arguments" => "{}"}}.to_json),
      ]
      history.append_message(LLM::Message::Response.new(nil, nil, tool_calls_json))
      history.append_message(LLM::Message::ToolCall.new("call_1", "echo", "tool result"))
      history.append_message(LLM::Message::Response.new("Final response", nil))
      history
    end

    # Collect all messages from a history into an array for inspection.
    private def collect_messages(history : LLM::History) : Array(LLM::Message)
      messages = [] of LLM::Message
      history.each_message(reverse: false) do |msg|
        messages << msg
      end
      messages
    end

    # Helper to extract text from a MultiContent message's first content element.
    private def multi_content_text(msg : LLM::Message) : String
      msg.as(LLM::Message::MultiContent).content.first.as(LLM::Content::Text).text
    end

    it "squishes all turns with skip_turns=0, dropping intermediate tool calls" do
      history = build_two_turn_history_with_tools
      squished = history.squish_turns(skip_turns: 0).not_nil!

      messages = collect_messages(squished)

      # Expected: MultiContent("First prompt"), Response("First response"),
      #           MultiContent("Second prompt"), Response("Final response")
      # The intermediate Response(tool_calls) and ToolCall are dropped;
      # the final Response("Final response") is appended after the loop.
      expect(messages.size).to eq(4)

      # Message 0: MultiContent("First prompt")
      expect(messages[0]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[0])).to eq("First prompt")

      # Message 1: Response("First response")
      expect(messages[1]).to be_a(LLM::Message::Response)
      expect(messages[1].as(LLM::Message::Response).content).to eq("First response")

      # Message 2: MultiContent("Second prompt")
      expect(messages[2]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[2])).to eq("Second prompt")

      # Message 3: Response("Final response")
      expect(messages[3]).to be_a(LLM::Message::Response)
      expect(messages[3].as(LLM::Message::Response).content).to eq("Final response")
    end

    it "squishes with skip_turns=1, preserving the last turn entirely" do
      history = build_two_turn_history_with_tools
      squished = history.squish_turns(skip_turns: 1).not_nil!

      messages = collect_messages(squished)

      # Turn 0 is squished: MultiContent("First prompt"), Response("First response")
      # Turn 1 is preserved entirely: MultiContent("Second prompt"), Response(tool_calls), ToolCall, Response("Final response")
      expect(messages.size).to eq(6)

      # --- Squished turn 0 ---
      # Message 0: MultiContent("First prompt")
      expect(messages[0]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[0])).to eq("First prompt")

      # Message 1: Response("First response")
      expect(messages[1]).to be_a(LLM::Message::Response)
      expect(messages[1].as(LLM::Message::Response).content).to eq("First response")

      # --- Preserved turn 1 ---
      # Message 2: MultiContent("Second prompt")
      expect(messages[2]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[2])).to eq("Second prompt")

      # Message 3: Response with tool_calls
      expect(messages[3]).to be_a(LLM::Message::Response)
      resp3 = messages[3].as(LLM::Message::Response)
      expect(resp3.content).to be_nil
      expect(resp3.tool_calls).not_to be_nil
      expect(resp3.tool_calls.not_nil!.size).to eq(1)

      # Message 4: ToolCall
      expect(messages[4]).to be_a(LLM::Message::ToolCall)
      tc = messages[4].as(LLM::Message::ToolCall)
      expect(tc.tool_call_id).to eq("call_1")
      expect(tc.name).to eq("echo")
      expect(tc.content).to eq("tool result")

      # Message 5: Response("Final response")
      expect(messages[5]).to be_a(LLM::Message::Response)
      expect(messages[5].as(LLM::Message::Response).content).to eq("Final response")
    end

    it "squishes a simple 3-turn history with skip_turns=0" do
      history = LLM::History.new
      history.append_message(LLM::Message::MultiContent.new("A"))
      history.append_message(LLM::Message::Response.new("a", nil))
      history.append_message(LLM::Message::MultiContent.new("B"))
      history.append_message(LLM::Message::Response.new("b", nil))
      history.append_message(LLM::Message::MultiContent.new("C"))
      history.append_message(LLM::Message::Response.new("c", nil))

      squished = history.squish_turns(skip_turns: 0).not_nil!
      messages = collect_messages(squished)

      # Algorithm: each turn's MultiContent triggers appending the previous turn's last response.
      # The final Response("c") is appended after the loop completes.
      # Result: MultiContent("A"), Response("a"), MultiContent("B"), Response("b"), MultiContent("C"), Response("c")
      expect(messages.size).to eq(6)

      expect(messages[0]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[0])).to eq("A")

      expect(messages[1]).to be_a(LLM::Message::Response)
      expect(messages[1].as(LLM::Message::Response).content).to eq("a")

      expect(messages[2]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[2])).to eq("B")

      expect(messages[3]).to be_a(LLM::Message::Response)
      expect(messages[3].as(LLM::Message::Response).content).to eq("b")

      expect(messages[4]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[4])).to eq("C")

      expect(messages[5]).to be_a(LLM::Message::Response)
      expect(messages[5].as(LLM::Message::Response).content).to eq("c")
    end

    describe "returns nil when skip_turns >= total_turns" do
      it "returns nil when skip_turns equals total_turns" do
        history = build_two_turn_history_with_tools
        expect(history.squish_turns(skip_turns: 2)).to be_nil
      end

      it "returns nil when skip_turns greatly exceeds total_turns" do
        history = build_two_turn_history_with_tools
        expect(history.squish_turns(skip_turns: 99)).to be_nil
      end
    end

    it "returns nil for an empty history" do
      history = LLM::History.new
      expect(history.squish_turns(skip_turns: 0)).to be_nil
    end

    it "squishes a single turn with skip_turns=0, keeping the MultiContent and Response" do
      history = LLM::History.new
      history.append_message(LLM::Message::MultiContent.new("Only"))
      history.append_message(LLM::Message::Response.new("Only response", nil))

      squished = history.squish_turns(skip_turns: 0).not_nil!
      messages = collect_messages(squished)

      # The MultiContent is kept and the Response is appended after the loop.
      expect(messages.size).to eq(2)
      expect(messages[0]).to be_a(LLM::Message::MultiContent)
      expect(multi_content_text(messages[0])).to eq("Only")

      expect(messages[1]).to be_a(LLM::Message::Response)
      expect(messages[1].as(LLM::Message::Response).content).to eq("Only response")
    end
  end
end
