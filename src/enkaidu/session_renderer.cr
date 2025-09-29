module Enkaidu
  # SessionRenderer defines the interface for rendering session output and
  # user prompts within the Enkaidu application. These are callbacks from the app session
  # so that we can implement different rendering systems.
  abstract class SessionRenderer
    abstract def info_with(message, help = nil, markdown = false)

    abstract def warning_with(message, help = nil, markdown = false)

    abstract def error_with(message, help = nil, markdown = false)

    abstract def user_query(query)

    abstract def user_confirm_shell_command?(command)

    abstract def session_reset

    abstract def llm_tool_call(name, args)

    abstract def llm_text(text)

    abstract def llm_text_block(text)

    abstract def llm_error(err)

    abstract def mcp_initialized(uri)

    abstract def mcp_tools_found(count)

    abstract def mcp_tool_ready(function)

    abstract def mcp_prompts_found(count)

    abstract def mcp_prompt_ready(prompt)

    abstract def mcp_calling_tool(uri, name, args)

    abstract def mcp_calling_tool_result(uri, name, result)

    abstract def mcp_error(ex)
  end
end
