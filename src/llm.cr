require "./llm/local_function"
require "./llm/connection"
require "./llm/azure_openai"
require "./llm/gemini_openai"
require "./llm/ollama"

module LLM
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
  # `openai`, `ollama`, `azure_openai`, or `gemini_openai`) or `nil` if unknown.
  def self.connection_by(provider : String) : Connection?
    case provider
    when "openai"        then OpenAI::Connection.new
    when "ollama"        then Ollama::Connection.new
    when "azure_openai"  then AzureOpenAI::Connection.new
    when "gemini_openai" then GeminiOpenAI::Connection.new
    end
  end
end
