require "../../spec_helper"

# Exercise the same queue-then-execute pattern as Session, including history.
class ResponsesFailureTestChat < LLM::Protocol::Responses::Chat
  def consume_test_stream(body : String, & : LLM::ChatEvent ->) : Nil
    response = ResponsesFailureTestResponse.new(IO::Memory.new(body))
    handle_text_event_stream(response) { |event| yield event }
  end
end

record ResponsesFailureTestResponse, body_io : IO::Memory

def failure_sse(*payloads : String) : String
  payloads.map { |payload| "data: #{payload}\n\n" }.join
end

Spectator.describe "Responses stream failure safety" do
  include LLMSpecHelpers

  it "does not execute already finished or pending calls after failed, incomplete, error or truncated streams" do
    terminals = [
      %q|{"type":"response.failed","response":{"status":"failed"}}|,
      %q|{"type":"error","message":"failure"}|,
      %q|{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}|,
      %q|{"type":"response.completed","response":{"status":"incomplete"}}|,
      "[DONE]",
      "",
    ]
    terminals.each do |terminal|
      chat = ResponsesFailureTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
      chat.with_tool(TestEchoTool.new)
      chat.append_message(LLM::Message::MultiContent.new(prompt: "test"))
      before = save_chat_json(chat)
      calls = [] of LLM::FunctionCall
      events = [] of LLM::ChatEvent
      body = failure_sse(
        %q|{"type":"response.output_text.delta","delta":"partial"}|,
        %q|{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","call_id":"one","name":"echo","arguments":"{\"value\":\"x\"}"}}|,
        %q|{"type":"response.function_call_arguments.done","output_index":0}|,
        %q|{"type":"response.output_item.added","output_index":1,"item":{"type":"function_call","call_id":"two","name":"echo","arguments":"{\"value\":"}}|,
        terminal,
      )
      expect do
        chat.consume_test_stream(body) do |event|
          events << event
          calls << LLM::FunctionCall.from_json(event[:content]) if event[:type].tool_call_requested?
        end
      end.to raise_error(LLM::Error)
      invoked = 0
      chat.call_tools_and_setup_ask(calls) { |event| invoked += 1 if event[:type].calling_tool? }
      expect(invoked).to eq(0)
      expect(calls).to be_empty
      expect(save_chat_json(chat)).to eq(before)
      expect(events.any? { |event| event[:type].done? }).to be_false
    end
  end

  it "publishes and commits calls only after successful response completion" do
    chat = ResponsesFailureTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
    chat.append_message(LLM::Message::MultiContent.new(prompt: "test"))
    before = save_chat_json(chat)
    events = [] of LLM::ChatEvent
    body = failure_sse(
      %q|{"type":"response.output_item.added","item":{"type":"function_call","call_id":"one","name":"echo","arguments":"{}"}}|,
      %q|{"type":"response.function_call_arguments.done","item_id":"one"}|,
      %q|{"type":"response.completed","response":{"status":"completed"}}|,
    )
    chat.consume_test_stream(body) { |event| events << event }
    expect(events.count { |event| event[:type].tool_call_requested? }).to eq(1)
    expect(events.count { |event| event[:type].done? }).to eq(1)
    expect(save_chat_json(chat)).not_to eq(before)
  end

  it "warns and proceeds with completed calls when [DONE] arrives without response.completed" do
    chat = ResponsesFailureTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
    chat.with_tool(TestEchoTool.new)
    chat.append_message(LLM::Message::MultiContent.new(prompt: "test"))
    before = save_chat_json(chat)
    calls = [] of LLM::FunctionCall
    events = [] of LLM::ChatEvent
    body = failure_sse(
      %q|{"type":"response.output_text.delta","delta":"partial"}|,
      %q|{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","call_id":"one","name":"echo","arguments":"{\"value\":\"x\"}"}}|,
      %q|{"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","call_id":"one","name":"echo","arguments":"{\"value\":\"x\"}"}}|,
      "[DONE]",
    )
    chat.consume_test_stream(body) do |event|
      events << event
      calls << LLM::FunctionCall.from_json(event[:content]) if event[:type].tool_call_requested?
    end
    invoked = 0
    chat.call_tools_and_setup_ask(calls) { |event| invoked += 1 if event[:type].calling_tool? }
    expect(invoked).to eq(1)
    expect(calls.size).to eq(1)
    expect(events.count { |event| event[:type].warn_unexpected? }).to eq(1)
    expect(events.count { |event| event[:type].done? }).to eq(1)
    expect(save_chat_json(chat)).not_to eq(before)
  end

  it "does not proceed when [DONE] arrives with an empty stream" do
    chat = ResponsesFailureTestChat.new(LLM::Ollama::Connection.new(LLM::ProtocolKind::Responses))
    chat.append_message(LLM::Message::MultiContent.new(prompt: "test"))
    before = save_chat_json(chat)
    events = [] of LLM::ChatEvent
    body = failure_sse("[DONE]")
    expect do
      chat.consume_test_stream(body) { |event| events << event }
    end.to raise_error(LLM::UnexpectedResponseError)
    expect(events.any? { |event| event[:type].done? }).to be_false
    expect(save_chat_json(chat)).to eq(before)
  end
end
