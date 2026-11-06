require "../../spec_helper"

class SchemaPropagationTestChat < LLM::Chat
  getter reask_schemas = [] of LLM::ResponseSchema?

  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end

  def call_tools_and_setup_ask(tool_calls : Array(LLM::FunctionCall), & : LLM::ChatEvent ->) : Int32
    1
  end

  def re_ask(response_schema : LLM::ResponseSchema? = nil,
             exclude_reasoning_in_history = false,
             exclude_reasoning_skip = 0,
             & : LLM::ChatEvent ->) : Nil
    @reask_schemas << response_schema
  end
end

class SchemaPropagationTestProgress
  property label : String = ""

  def start : Nil
  end

  def stop : Nil
  end
end

class SchemaPropagationTestSession < Enkaidu::Session
  def self.for_test(chat : LLM::Chat) : self
    session = uninitialized self
    session.setup_for_test(chat)
    session
  end

  def setup_for_test(chat : LLM::Chat) : Nil
    @chat = chat
  end

  def consume_for_test(tool_calls : Array(LLM::FunctionCall), schema : LLM::ResponseSchema?) : Nil
    consume_tool_calls_sync(tool_calls, SchemaPropagationTestProgress.new, schema)
  end
end

Spectator.describe "Enkaidu::Session structured-output schema propagation" do
  it "retains the schema when asking again after a tool call" do
    chat = SchemaPropagationTestChat.new
    session = SchemaPropagationTestSession.for_test(chat)
    schema = LLM::ResponseSchema.from_json(%({"name":"answer","description":"","schema":{"type":"object","properties":{"ok":{"type":"boolean"}}},"strict":true}))
    tool_call = LLM::FunctionCall.new("call_1", "example", "{}")

    session.consume_for_test([tool_call], schema)

    expect(chat.reask_schemas).to eq([schema])
  end
end
