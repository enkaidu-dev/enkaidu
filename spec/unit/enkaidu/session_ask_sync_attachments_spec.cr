require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

# Mock chat that records how `ask_sync` invokes `chat.ask` and emits no events.
class AskSyncAttachmentsProbeChat < LLM::Chat
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

class AskSyncAttachmentsProbeSession < EnkaiduWiretapTestSession
  def set_mock_chat(mock_chat : LLM::Chat)
    @chat = mock_chat
  end
end

Spectator.describe "Enkaidu::Session ask_sync attachments and schema forwarding" do
  include LLMSpecHelpers

  it "forwards the query, attachments, and response schema to chat.ask" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = AskSyncAttachmentsProbeSession.new(renderer, options)
      mock_chat = AskSyncAttachmentsProbeChat.new
      session.set_mock_chat(mock_chat)

      attach = LLM::ChatInclusions.new
      attach.text("attached text", "attachment.txt")
      schema = LLM::ResponseSchema.from_json(
        %({"name":"answer","description":"","schema":{"type":"object","properties":{"ok":{"type":"boolean"}}},"strict":true}))

      session.ask_sync(query: "with attachments", attach: attach, response_json_schema: schema)

      expect(mock_chat.ask_contents).to eq(["with attachments"])
      expect(mock_chat.ask_attach).to eq([attach])
      expect(mock_chat.ask_schemas).to eq([schema])
    end
  end

  it "forwards exclusion flags derived from session settings" do
    with_ollama_envs do
      scenarios = [
        {config_yaml: "", exclude: false, skip: -1},
        {config_yaml: "session:\n  exclude_past_reasoning: true\n", exclude: true, skip: 0},
        {config_yaml: "session:\n  exclude_past_reasoning: 5\n", exclude: true, skip: 5},
      ]

      scenarios.each do |scenario|
        renderer = EnkaiduWiretapTestRenderer.new
        options = EnkaiduUniqueModelTestOptions.new(renderer, scenario[:config_yaml])
        session = AskSyncAttachmentsProbeSession.new(renderer, options)
        mock_chat = AskSyncAttachmentsProbeChat.new
        session.set_mock_chat(mock_chat)

        session.ask_sync(query: "exclusion check")

        expect(mock_chat.ask_exclude_reasoning).to eq([scenario[:exclude]])
        expect(mock_chat.ask_exclude_skip).to eq([scenario[:skip]])
      end
    end
  end
end