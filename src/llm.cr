require "./llm/local_function"
require "./llm/connection"
require "./llm/azure_openai"
require "./llm/ollama"

module LLM
  # Development use; set to `true` to trace HTTP
  TRACE = false
end
