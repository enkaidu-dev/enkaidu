require "../../spec_helper"
require "http"
require "json"

# Connectivity probe for the local Ollama endpoint, representative of the
# Responses protocol spec set (the endpoint and recorded transcript are shared).
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
