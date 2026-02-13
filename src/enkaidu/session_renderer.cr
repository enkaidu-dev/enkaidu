require "./mcp_prompt"
require "./template_prompt"

module Enkaidu
  # SessionRenderer defines the interface for rendering session output and
  # user prompts within the Enkaidu application. These are callbacks from the app session
  # so that we can implement different rendering systems.
  abstract class SessionRenderer
    abstract def info_with(message, help = nil, markdown = false)

    abstract def warning_with(message, help = nil, markdown = false)

    abstract def error_with(message, help = nil, markdown = false)

    abstract def user_query_text(query, via_macro = false)
    abstract def user_query_image_url(url)

    abstract def user_confirm_shell_command?(command)

    abstract def user_prompt_ask_input(prompt : TemplatePrompt) : Hash(String, String)

    abstract def time_elapsed(duration : Time::Span, label : String? = nil)

    abstract def session_reset
    abstract def session_pushed(depth, keep_tools, keep_prompts, keep_history)
    abstract def session_popped(depth)

    abstract def session_stack_new(name)
    abstract def session_stack_changed(name)

    abstract def llm_tool_call(name, args)

    abstract def llm_text(text, reasoning : Bool)
    abstract def llm_text_block(text, reasoning : Bool)
    abstract def llm_image_url(url)

    abstract def llm_error(err)

    abstract def mcp_initialized(uri)

    abstract def mcp_tools_found(count)

    abstract def mcp_tool_ready(function)

    abstract def mcp_prompts_found(count)

    abstract def mcp_prompt_ready(prompt)

    abstract def mcp_prompt_ask_input(prompt : MCPPrompt) : Hash(String, String)

    abstract def mcp_calling_tool(uri, name, args)

    abstract def mcp_calling_tool_result(uri, name, result)

    abstract def mcp_error(ex)
  end
end
