require "../../spec_helper"
require "http"
require "json"

# Connectivity probe for the local Ollama endpoint, run through wiretap.
#
# This is the first LLM spec on purpose: it isolates the "can the test
# sandbox reach localhost:11434?" question from the module-under-test.
# On the first run it records the model-list transcript; on later runs
# (and in CI) it replays it with no network.
Spectator.describe LLM do
  include LLMSpecHelpers

  describe "Ollama provider (local)" do
    it "reaches the OpenAI-compatible endpoint and lists the model" do
      Wiretap.intercept("ollama_list_models") do
        client = HTTP::Client.new(URI.parse(LLMSpecHelpers::OLLAMA_ENDPOINT))
        response = client.exec(HTTP::Request.new("GET", "/v1/models"))
        expect(response.status.code).to eq(200)

        ids = JSON.parse(response.body)["data"].as_a.map { |m| m["id"].as_s }
        expect(ids).not_to be_empty
        expect(ids.any? { |id| id.includes?("ornith") }).to be_true
      end
    end
  end
end
