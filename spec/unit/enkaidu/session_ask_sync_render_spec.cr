require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Captures calls to `user_query_text` so the `render_query` flag can be asserted.
class AskSyncRenderProbeRenderer < EnkaiduWiretapTestRenderer
  getter rendered_queries = [] of String

  def user_query_text(query, via_query_queue = false)
    @rendered_queries << query.to_s
  end
end

# Mock chat that records how `ask_sync` invokes `chat.ask` and emits no events.
class AskSyncProbeChat < LLM::Chat
  getter ask_contents = [] of String
  getter ask_attach = [] of LLM::ChatInclusions?
  getter ask_schemas = [] of LLM::ResponseSchema?
  getter ask_exclude_reasoning = [] of Bool
  getter ask_exclude_skip = [] of Int32

  def ask(content : String,
          attach : LLM::ChatInclusions? = nil,
          response_schema : LLM::ResponseSchema? = nil,
          exclude_reasoning_in_history = false,
          exclude_reasoning_skip = 0,
          & : LLM::ChatEvent ->) : Nil
    @ask_contents << content
    @ask_attach << attach
    @ask_schemas << response_schema
    @ask_exclude_reasoning << exclude_reasoning_in_history
    @ask_exclude_skip << exclude_reasoning_skip
    nil
  end

  def post_session(response_schema : LLM::ResponseSchema? = nil,
                   exclude_reasoning_in_history = false,
                   exclude_reasoning_skip = 0,
                   & : LLM::ChatEvent ->) : Nil
  end
end

class AskSyncProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session ask_sync query rendering" do
  include LLMSpecHelpers

  it "renders the query text only when render_query is true" do
    with_ollama_envs do
      renderer = AskSyncRenderProbeRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = AskSyncProbeSession.new(renderer, options)
      mock_chat = AskSyncProbeChat.new
      session.set_mock_chat(mock_chat)

      session.ask_sync(query: "plain query", render_query: false)
      session.ask_sync(query: "rendered query", render_query: true)

      expect(renderer.rendered_queries).to eq(["rendered query"])
      # Rendering must not change what the chat receives.
      expect(mock_chat.ask_contents).to eq(["plain query", "rendered query"])
    end
  end
end