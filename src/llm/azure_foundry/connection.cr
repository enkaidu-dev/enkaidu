require "http/client"
require "uri"

require "../openai"

module LLM::AzureFoundry
  # `Connection` is a class that extends from `OpenAI::Connection` to provide
  # specialized connection handling for Azure OpenAI services.
  class Connection < OpenAI::Connection
    def api_key : String
      ENV.fetch("AZURE_FOUNDRY_API_KEY", nil) || raise MissingAPIKey.new("Azure OpenAI connections require an API key.")
    end

    def model
      super || ENV["AZURE_FOUNDRY_MODEL"]?
    end

    protected def url : String
      ENV["AZURE_FOUNDRY_ENDPOINT"]
    end

    protected def path : String
      "/openai/v1/chat/completions"
    end
  end
end
