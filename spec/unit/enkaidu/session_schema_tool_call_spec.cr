require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session structured output across Ollama tool calls" do
  include EnkaiduSessionWiretapHelpers

  it "resends the requested JSON schema after a tool call for both protocols" do
    # Ollama's grammar-based format implementation accepts a limited schema
    # subset. Keep this test schema minimal and avoid draft/version metadata,
    # descriptions, and validation keywords such as `required` / `minLength`.
    schema = LLM::ResponseSchema.from_json(
      %({"name":"session_answer","description":"Response echoed back","schema":{"type":"object","properties":{"echoed":{"type":"string"}}},"strict":false}))

    [
      {kind: LLM::ProtocolKind::ChatCompletions, transcript: "enkaidu_session_cc_schema_tool_call"},
      {kind: LLM::ProtocolKind::Responses, transcript: "enkaidu_session_responses_schema_tool_call"},
    ].each do |scenario|
      with_ollama_envs do
        renderer = EnkaiduWiretapTestRenderer.new
        provider = scenario[:kind].responses? ? "ollama:responses" : "ollama"
        options = EnkaiduWiretapTestOptions.new(renderer, provider)
        session = EnkaiduWiretapTestSession.new(renderer, options)
        session.install_tool(TestEchoTool.new)

        Wiretap.intercept(scenario[:transcript]) do
          session.ask_sync(ENKAIDU_SCHEMA_TOOL_PROMPT, response_json_schema: schema)
        end

        raise "#{scenario[:transcript]} session errors: #{renderer.errors.join("; ")}" unless renderer.errors.empty?
        expect(renderer.tool_calls).to eq(["echo"])

        requests = enkaidu_schema_tool_request_bodies(scenario[:transcript])
        expect(requests.size).to eq(2)
        requests.each do |request|
          format = if response_format = request["response_format"]?
                     expect(response_format["type"].as_s).to eq("json_schema")
                     response_format["json_schema"]
                   else
                     request.dig("text", "format")
                   end
          expect(format["name"].as_s).to eq("session_answer")
          expect(format.dig("schema", "properties", "echoed", "type").as_s).to eq("string")
        end
      end
    end
  end
end
