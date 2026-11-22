require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that drives `ask_sync` through multiple tool-call rounds: `ask`
# emits the first ToolCallRequested, and each positive
# `call_tools_and_setup_ask` count triggers a `re_ask` that emits one more
# ToolCallRequested. The final round reports 0, ending the loop.
class SchemaMultiRoundProbeChat < LLM::Chat
  getter loop_steps = [] of String
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
    # Every re_ask asks for one more tool call so the loop keeps going.
    names = %w[tool-one tool-two tool-three]
    yield tool_call_event(names[@re_ask_count], "#{@re_ask_count + 1}")
    nil
  end

  def call_tools_and_setup_ask(tool_calls : Array(LLM::FunctionCall), & : LLM::ChatEvent ->) : Int32
    @call_tools_round += 1
    @loop_steps << "call_tools_and_setup_ask"
    @tool_call_rounds << tool_calls
    # Positive counts keep the loop going; the final round reports none.
    @call_tools_round < 3 ? 1 : 0
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

class SchemaMultiRoundProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session re_ask schema propagation across tool-call rounds" do
  include LLMSpecHelpers

  it "forwards the response schema to every re_ask across multiple tool-call rounds" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = SchemaMultiRoundProbeSession.new(renderer, options)
      mock_chat = SchemaMultiRoundProbeChat.new
      session.set_mock_chat(mock_chat)

      schema = LLM::ResponseSchema.from_json(%({
        "name": "answer",
        "description": "Answer the question.",
        "schema": {"type": "object", "properties": {"ok": {"type": "boolean"}}},
        "strict": true
      }))

      session.ask_sync(query: "use the tools", response_json_schema: schema)

      # ask -> call_tools_and_setup_ask -> re_ask -> call_tools_and_setup_ask -> re_ask -> call_tools_and_setup_ask -> done
      expect(mock_chat.loop_steps).to eq([
        "ask",
        "call_tools_and_setup_ask",
        "re_ask",
        "call_tools_and_setup_ask",
        "re_ask",
        "call_tools_and_setup_ask",
      ])

      # Each round receives the tool calls collected from the previous round.
      expect(mock_chat.tool_call_rounds.map { |calls| calls.map { |call| [call.id, call.name] } }).to eq([
        [["1", "tool-one"]],
        [["2", "tool-two"]],
        [["3", "tool-three"]],
      ])

      # The schema reaches the initial ask and every re_ask in every round.
      expect(mock_chat.ask_schemas).to eq([schema])
      expect(mock_chat.re_ask_schemas).to eq([schema, schema])
    end
  end
end
