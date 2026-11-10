require "http/client"
require "uri"

require "../openai"

module LLM::AzureFoundry
  # `Connection` is a class that extends from `OpenAI::Connection` to provide
  # specialized connection handling for Azure OpenAI services.
  class Connection < OpenAI::Connection
    private API_KEY_ENV_NAME = "AZURE_FOUNDRY_API_KEY"

    def api_key : String
      ENV.fetch(API_KEY_ENV_NAME, nil) || raise MissingAPIKey.new("Azure AI Foundry requires an API key, Missing env var: #{API_KEY_ENV_NAME}")
    end

    def model
      super || ENV["AZURE_FOUNDRY_MODEL"]?
    end

    protected def url : String
      ENV["AZURE_FOUNDRY_ENDPOINT"]
    end

    protected def path : String
      # Prepend `/openai` to the standard Open AI path
      "/openai#{super}"
    end
  end
end
