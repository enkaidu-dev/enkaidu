require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that records the tool-call loop and drives a controlled number of
# tool calls: the first `call_tools_and_setup_ask` reports one call (which makes
# the session `re_ask`), and that first `re_ask` requests a second tool; the
# second `call_tools_and_setup_ask` reports none, ending the loop.
class AskSyncToolLoopProbeChat < LLM::Chat
  getter loop_steps = [] of String
  getter ask_queries = [] of String
  getter ask_schemas = [] of LLM::ResponseSchema?
  getter re_ask_schemas = [] of LLM::ResponseSchema?
  getter tool_call_rounds = [] of Array(LLM::FunctionCall)
  getter re_ask_count = 0
  getter call_tools_round = 0

  def ask(content : String,
          attach : LLM::ChatInclusions? = nil,
          response_schema : LLM::ResponseSchema? = nil,
          exclude_reasoning_in_history = false,
          exclude_reasoning_skip = 0,
          & : LLM::ChatEvent ->) : Nil
    @loop_steps << "ask"
    @ask_queries << content
    @ask_schemas << response_schema
    yield tool_call_event("tool-one", "1")
    nil
  end

  def re_ask(response_schema : LLM::ResponseSchema? = nil,
             exclude_reasoning_in_history = false,
             exclude_reasoning_skip = 0,
             & : LLM::ChatEvent ->) : Nil
    @re_ask_count += 1
    @loop_steps << "re_ask"
    @re_ask_schemas << response_schema
    # First re_ask asks for a second tool call so the loop runs another round.
    yield tool_call_event("tool-two", "2") if @re_ask_count == 1
    nil
  end

  def call_tools_and_setup_ask(tool_calls : Array(LLM::FunctionCall), & : LLM::ChatEvent ->) : Int32
    @call_tools_round += 1
    @loop_steps << "call_tools_and_setup_ask"
    @tool_call_rounds << tool_calls
    # First round reports a call (so the session re-asks); second round is done.
    @call_tools_round == 1 ? 1 : 0
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

class AskSyncToolLoopProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session ask_sync tool-call loop" do
  include LLMSpecHelpers

  it "collects ToolCallRequested events, invokes tools, and re-asks until no calls remain" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = AskSyncToolLoopProbeSession.new(renderer, options)
      mock_chat = AskSyncToolLoopProbeChat.new
      session.set_mock_chat(mock_chat)

      schema = LLM::ResponseSchema.from_json(
        %({"name":"answer","description":"","schema":{"type":"object","properties":{"ok":{"type":"boolean"}}},"strict":true}))

      session.ask_sync(query: "use the tools", response_json_schema: schema)

      # ask -> call_tools_and_setup_ask -> re_ask -> (second round) call_tools_and_setup_ask -> done
      expect(mock_chat.loop_steps).to eq([
        "ask",
        "call_tools_and_setup_ask",
        "re_ask",
        "call_tools_and_setup_ask",
      ])

      # Both rounds invoke the collected tool calls in order.
      expect(mock_chat.tool_call_rounds.map { |calls| calls.map { |call| [call.id, call.name] } }).to eq([
        [["1", "tool-one"]],
        [["2", "tool-two"]],
      ])

      # The query and response schema are forwarded to ask and to every re_ask.
      expect(mock_chat.ask_queries).to eq(["use the tools"])
      expect(mock_chat.ask_schemas).to eq([schema])
      expect(mock_chat.re_ask_schemas).to eq([schema])
    end
  end
end