require "../../spec_helper"

# Exercise the production response handlers and tool execution without HTTP.
class EncryptedReasoningTestChat < LLM::Protocol::Responses::Chat
  def consume_json(body : String, & : LLM::ChatEvent ->) : Nil
    handle_app_json(EncryptedReasoningTestResponse.new(IO::Memory.new(body))) { |event| yield event }
  end

  def consume_stream(body : String, & : LLM::ChatEvent ->) : Nil
    handle_text_event_stream(EncryptedReasoningTestResponse.new(IO::Memory.new(body))) { |event| yield event }
  end

  def request_body : JSON::Any
    JSON.parse(to_body)
  end
end

record EncryptedReasoningTestResponse, body_io : IO::Memory

Spectator.describe "Responses encrypted reasoning in tool loops" do
  include LLMSpecHelpers

  it "replays empty-summary reasoning before the tool call and result for JSON and SSE" do
    [false, true].each do |streaming|
      chat = EncryptedReasoningTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
      chat.with_tool(TestEchoTool.new)
      chat.with_streaming if streaming
      chat.append_message(LLM::Message::MultiContent.new(prompt: "echo x"))
      events = [] of LLM::ChatEvent
      if streaming
        body = [
          %q|{"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_loop","summary":[]}}|,
          %q|{"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_loop","summary":[],"encrypted_content":"secret_loop"}}|,
          %q|{"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","call_id":"call_loop","name":"echo","arguments":"{\"value\":\"x\"}"}}|,
          %q|{"type":"response.output_item.done","output_index":1,"item":{"type":"function_call","call_id":"call_loop","name":"echo","arguments":"{\"value\":\"x\"}"}}|,
          %q|{"type":"response.completed","response":{"status":"completed"}}|,
        ].map { |payload| "data: #{payload}\n\n" }.join
        chat.consume_stream(body) { |event| events << event }
      else
        body = %q|{"status":"completed","output":[{"type":"reasoning","id":"rs_loop","summary":[],"encrypted_content":"secret_loop"},{"type":"function_call","call_id":"call_loop","name":"echo","arguments":"{\"value\":\"x\"}"}]}|
        chat.consume_json(body) { |event| events << event }
      end

      calls = events.select { |event| event[:type].tool_call_requested? }.map { |event| LLM::FunctionCall.from_json(event[:content]) }
      expect(calls.size).to eq(1)
      expect(chat.call_tools_and_setup_ask(calls) { |_| }).to eq(1)
      input = chat.request_body["input"].as_a
      expect(input.size).to eq(4)
      if input.size == 4
        expect(input[0]["role"].as_s).to eq("user")
        expect(input[1]["type"].as_s).to eq("reasoning")
        expect(input[1]["id"].as_s).to eq("rs_loop")
        expect(input[1]["encrypted_content"].as_s).to eq("secret_loop")
        expect(input[1]["summary"].as_a).to be_empty
        expect(input[2]["type"].as_s).to eq("function_call")
        expect(input[2]["call_id"].as_s).to eq("call_loop")
        expect(input[3]["type"].as_s).to eq("function_call_output")
        expect(input[3]["call_id"].as_s).to eq("call_loop")
        expect(JSON.parse(input[3]["output"].as_s)["echoed"].as_s).to eq("x")
      end
    end
  end

  it "uses the completed reasoning metadata when the added item has empty placeholders" do
    chat = EncryptedReasoningTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
    body = [
      %q|{"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"","summary":[],"encrypted_content":""}}|,
      %q|{"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_final","summary":[],"encrypted_content":"secret_final"}}|,
      %q|{"type":"response.completed","response":{"status":"completed"}}|,
    ].map { |payload| "data: #{payload}\n\n" }.join
    chat.consume_stream(body) { |_| }

    restored = EncryptedReasoningTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
    restored.load(save_chat_json(chat))
    replay = restored.request_body["input"].as_a.find { |item| item["type"]?.try(&.as_s?) == "reasoning" }
    expect(replay).not_to be_nil
    if replay
      expect(replay["id"].as_s).to eq("rs_final")
      expect(replay["encrypted_content"].as_s).to eq("secret_final")
      expect(replay["summary"].as_a).to be_empty
    end
  end

  it "preserves explicit exclusion through a history save and load" do
    chat = EncryptedReasoningTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
    response = LLM::Message::Response.new(nil, nil, reasoning_id: "rs_hidden", encrypted_content: "secret")
    response.include_reasoning = false
    chat.append_message(response)
    restored = EncryptedReasoningTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
    restored.load(save_chat_json(chat))
    expect(restored.request_body["input"].as_a).to be_empty
  end
end
