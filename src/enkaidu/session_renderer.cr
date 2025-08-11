# Defines callbacks from the app session
# so that we can implement different rendering systems
abstract class SessionRenderer
  abstract def warning(message)

  abstract def error_with(message, help = nil)

  abstract def user_query(query)

  abstract def user_calling_tools

  abstract def llm_tool_call(name, args)

  abstract def llm_text(text)

  abstract def llm_error(err)

  abstract def mcp_initialized(uri)

  abstract def mcp_tools_found(count)

  abstract def mcp_tool_ready(function)

  abstract def mcp_calling_tool(uri, name, args)

  abstract def mcp_calling_tool_result(uri, name, result)

  abstract def mcp_error(ex)
end
