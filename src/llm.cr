require "./llm/local_function"
require "./llm/connection"
require "./llm/azure_openai"
require "./llm/google_ai_studio"
require "./llm/ollama"

module LLM
  class Error < Exception; end

  # Development use; set to `true` to trace HTTP
  TRACE = false

  protected def self.show_error_trace(ex : Exception, data_label : String, data)
    msg = <<-ERROR
            ~~~{ unexpected - please report }~~~
            #{ex.inspect_with_backtrace}
            ~~~{ #{data_label} }~~~~~
            #{data}
            ~~~~~~~~~~~~~~~~~~~~
            ERROR
    STDERR.puts msg.colorize(:magenta)
  end

  # Returns an instance of a provider-specific `LLM::Connection`, for known `provider` (one of
  # `openai`, `ollama`, `azure_openai`, or `google_ai_studio`) or `nil` if unknown.
  def self.connection_by(provider : String) : Connection?
    case provider
    when "openai"           then OpenAI::Connection.new
    when "ollama"           then Ollama::Connection.new
    when "azure_openai"     then AzureOpenAI::Connection.new
    when "google_ai_studio" then GoogleAIStudio::Connection.new
    end
  end

  # Returns the provider label for the given connection instance
  def self.connection_provider_label(connection : Connection) : String
    case connection
    when LLM::Ollama::Connection      then "ollama"
    when LLM::AzureOpenAI::Connection then "azure_openai"
    when GoogleAIStudio::Connection   then "google_ai_studio"
    when LLM::OpenAI::Connection      then "openai"
    else
      raise Error.new("Unknown connection implementation: #{connection.class}")
    end
  end
end
