require "http/client"
require "uri"

require "../openai"

module LLM::AzureOpenAI
  class ChatConnection < OpenAI::ChatConnection
    def api_ver
      ENV["AZURE_OPENAI_API_VER"]
    end

    def api_key
      ENV["AZURE_OPENAI_API_KEY"]
    end

    def model
      ENV["AZURE_OPENAI_MODEL"]
    end

    protected def url : String
      ENV["AZURE_OPENAI_ENDPOINT"]
    end

    protected def path : String
      "/openai/deployments/#{model}/chat/completions?api-version=#{api_ver}"
    end

    protected def headers : HTTP::Headers
      HTTP::Headers{
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{api_key}",
      }
    end
  end
end
