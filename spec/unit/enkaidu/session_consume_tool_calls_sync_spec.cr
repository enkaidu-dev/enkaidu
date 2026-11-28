require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that drives `consume_tool_calls_sync` through three rounds of
# `call_tools_and_setup_ask`: it reports a controlled positive count on the
# first two rounds (so the session calls `chat.re_ask`) and 0 on the third
# (which ends the loop). Each `re_ask` emits a ToolCallRequested event, which
# the session collects into the next round's `tools`.
class ConsumeToolCallsProbeChat < LLM::Chat
  getter call_tools_invocations = 0
  getter call_tools_rounds = [] of Array(LLM::FunctionCall)
  getter re_ask_count = 0
  getter re_ask_schemas = [] of LLM::ResponseSchema?

  def call_tools_and_setup_ask(tool_calls : Array(LLM::FunctionCall), & : LLM::ChatEvent ->) : Int32
    @call_tools_invocations += 1
    @call_tools_rounds << tool_calls
    # Controlled counts per invocation: 2, then 1, then 0.
    [2, 1, 0][@call_tools_invocations - 1]
  end

  def re_ask(response_schema : LLM::ResponseSchema? = nil,
             exclude_reasoning_in_history = false,
             exclude_reasoning_skip = 0,
             & : LLM::ChatEvent ->) : Nil
    @re_ask_count += 1
    @re_ask_schemas << response_schema
    # Ask for another tool call so the loop runs one more round.
    names = %w[tool-one tool-two]
    yield tool_call_event(names[@re_ask_count - 1], "id-#{@re_ask_count}")
    nil
  end

  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end

  private def tool_call_event(name : String, id : String) : LLM::ChatEvent
    call = LLM::FunctionCall.new(id, name, %({{"value": name}}).to_json)
    {type: LLM::Event::ToolCallRequested, content: call.json}
  end
end

class ConsumeToolCallsProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end

  # `consume_tool_calls_sync` is private on `Enkaidu::Session`; this public
  # wrapper exercises it from the spec without changing the source.
  def run_consume_tool_calls_sync(tools : Array(LLM::FunctionCall),
                                  schema : LLM::ResponseSchema? = nil) : Nil
    consume_tool_calls_sync(tools, Enkaidu::Progress.new("Test"),
      response_json_schema: schema)
  end
end

Spectator.describe "Enkaidu::Session consume_tool_calls_sync multi-round" do
  include LLMSpecHelpers

  it "repeats call_tools_and_setup_ask until the count is empty and passes the schema to every re_ask" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = ConsumeToolCallsProbeSession.new(renderer, options)
      mock_chat = ConsumeToolCallsProbeChat.new
      session.set_mock_chat(mock_chat)

      schema = LLM::ResponseSchema.from_json(%({
        "name": "answer",
        "description": "Answer the question.",
        "schema": {"type": "object", "properties": {"ok": {"type": "boolean"}}},
        "strict": true
      }))

      initial_tools = [LLM::FunctionCall.new("id-0", "tool-zero", "{}")]
      session.run_consume_tool_calls_sync(initial_tools, schema)

      # Three rounds: the positive counts (2, 1) trigger a `re_ask`; the final
      # count of 0 ends the loop with no further `re_ask`.
      expect(mock_chat.call_tools_invocations).to eq(3)
      expect(mock_chat.re_ask_count).to eq(2)

      # Each round receives the tool calls collected from the previous
      # round's `re_ask` ToolCallRequested events.
      expect(mock_chat.call_tools_rounds.map { |calls| calls.map { |call| [call.id, call.name] } }).to eq([
        [["id-0", "tool-zero"]],
        [["id-1", "tool-one"]],
        [["id-2", "tool-two"]],
      ])

      # Every `re_ask` receives the same response schema.
      expect(mock_chat.re_ask_schemas).to eq([schema, schema])
    end
  end
end