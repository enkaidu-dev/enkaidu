require "http/client"
require "uri"

require "../openai"

module LLM::AzureOpenAI
  # `Connection` is a class that extends from `OpenAI::Connection` to provide
  # specialized connection handling for Azure OpenAI services.
  class Connection < OpenAI::Connection
    def initialize
      # Does not support Responses protocol
      super(ProtocolKind::ChatCompletions)
    end

    def api_ver
      ENV["AZURE_OPENAI_API_VER"]
    end

    private API_KEY_ENV_NAME = "AZURE_OPENAI_API_KEY"

    def api_key : String
      ENV.fetch(API_KEY_ENV_NAME, nil) || raise MissingAPIKey.new("Azure OpenAI requires an API key, Missing env var: #{API_KEY_ENV_NAME}")
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
