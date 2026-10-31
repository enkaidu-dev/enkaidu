require "http/client"
require "uri"

require "../openai"

module LLM::AzureOpenAI
  # `Connection` is a class that extends from `OpenAI::Connection` to provide
  # specialized connection handling for Azure OpenAI services.
  class Connection < OpenAI::Connection
    def api_ver
      ENV["AZURE_OPENAI_API_VER"]
    end

    def api_key : String
      ENV.fetch("AZURE_OPENAI_API_KEY", nil) || raise MissingAPIKey.new("Azure OpenAI connections require an API key.")
    end

    def model
      super || ENV["AZURE_OPENAI_MODEL"]?
    end

    protected def url : String
      ENV["AZURE_OPENAI_ENDPOINT"]
    end

    protected def path : String
      "/openai/deployments/#{model}/chat/completions?api-version=#{api_ver}"
    end
  end
end
