require "./llm/local_function"
require "./llm/connection"
require "./llm/azure_openai"
require "./llm/ollama"

module LLM
  # Development use; set to `true` to trace HTTP
  TRACE = false

  protected def self.show_error_trace(ex : Exception, data_label : String, data)
    msg = <<-ERROR
            ~~~{ unexpected - please report }~~~
            #{ex.inspect_with_backtrace}
            ~~~{ data_label }~~~~~
            #{data}
            ~~~~~~~~~~~~~~~~~~~~
            ERROR
    STDERR.puts msg.colorize(:magenta)
  end
end
