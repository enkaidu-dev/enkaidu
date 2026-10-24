require "http"
require "json"

# Shared scaffolding for the `Tools::Web` tool specs.
#
# The specs run without any network access: response handling is
# exercised by calling the runner's response methods directly with a
# `WebToolTestResponse`, and `#execute` is exercised up to the socket
# boundary (validation and host-policy checks happen before any fetch).

# A no-op renderer for building tools in tests, with a configurable
# permission response and a record of the permission questions asked.
class WebToolTestRenderer < Enkaidu::SessionRenderer
  property permission_response : Enkaidu::SessionRenderer::Permission
  getter permission_questions  : Array(String) = [] of String

  def initialize(
    @permission_response = Enkaidu::SessionRenderer::Permission.new(approved: false, remember: false)
  ); end

  def info_with(message, help = nil, markdown = false); end
  def warning_with(message, help = nil, markdown = false); end
  def error_with(message, help = nil, markdown = false); end
  def respond_with(message, help = nil, markdown = false); end
  def user_query_text(query, via_query_queue = false); end
  def user_query_image_url(url); end

  def user_permission_question(description, subject,
                               caution : String? = nil, banner : Enkaidu::SessionRenderer::Banner? = nil) : Enkaidu::SessionRenderer::Permission
    @permission_questions << subject.to_s
    @permission_response
  end

  def user_confirm_security_question?(description, subject,
                                      banner : NamedTuple(safe: Bool, message: String)? = nil) : Bool
    true
  end

  def user_prompt_ask_input(prompt : TemplatePrompt, params : Hash? = nil) : Hash(String, String)
    {} of String => String
  end

  def time_elapsed(duration : Time::Span, label : String? = nil) : Nil; end
  def session_reset(old_session : Enkaidu::Session, new_session : Enkaidu::Session) : Nil; end
  def session_pushed(depth, keep_tools, keep_prompts, keep_history) : Nil; end
  def session_popped(depth) : Nil; end
  def session_stack_new(name) : Nil; end
  def session_stack_changed(name) : Nil; end
  def llm_tool_call(name, args) : Nil; end
  def llm_text(text, reasoning : Bool, starting : Bool = false, ending : Bool = false) : Nil; end
  def llm_text_block(text, reasoning : Bool) : Nil; end
  def llm_image_url(url) : Nil; end
  def llm_error(err, message : String? = nil) : Nil; end
  def mcp_initialized(uri) : Nil; end
  def mcp_tools_found(count) : Nil; end
  def mcp_tool_ready(function) : Nil; end
  def mcp_prompts_found(count) : Nil; end
  def mcp_prompt_ready(prompt) : Nil; end

  def mcp_prompt_ask_input(prompt, params : Hash? = nil) : Hash(String, String)
    {} of String => String
  end

  def mcp_calling_tool(uri, name, args) : Nil; end
  def mcp_calling_tool_result(uri, name, result) : Nil; end
  def mcp_error(ex) : Nil; end
end

# A canned HTTP response for exercising response-handling methods
# without any network access.
class WebToolTestResponse
  getter status_code  : Int32
  getter content_type : String?
  getter body         : String

  def initialize(@status_code, @content_type : String? = nil, @body = "")
  end

  def body_io : IO
    io = IO::Memory.new
    io << @body
    io.rewind
    io
  end
end

# Helpers shared by the `Tools::Web` tool specs.
module WebToolSpecHelpers
  # Temp directory used by the web tool specs.
  WEB_TOOL_TEMP_DIR = "spec/tmp_http_web_test"

  # Parse a tool's JSON result string into {success, data, error_msg}.
  def parse_run_result(result_json)
    parsed = JSON.parse(result_json)
    hash = parsed.as_h?
    if hash
      err = hash["error"]?
      if err
        return {success: false, data: parsed, error_msg: err.as_s}
      end
    end
    {success: true, data: parsed, error_msg: nil}
  end

  # Execute a runner with the given string/bool arguments.
  def run_runner(runner, args : Hash(String, String | Bool))
    runner.execute(JSON.parse(args.to_json))
  end

  # Build web-tool settings. Defaults allow fetching loopback hosts
  # without prompting; pass `allowed_hosts: [] of String` to make every
  # host unknown (which triggers the user-permission flow).
  def web_tool_settings(allowed_hosts = ["127.0.0.1"] of String,
                        allow_private_hosts : Bool = true,
                        denied_hosts = [] of String) : LLM::Function::Settings
    LLM::Function::Settings.new.tap do |s|
      s["allowed_hosts"]       = allowed_hosts
      s["allow_private_hosts"] = allow_private_hosts
      s["denied_hosts"]        = denied_hosts
    end
  end

  # Create a canned HTTP response for the given content type and body.
  def web_response(body, content_type, status_code = 200)
    WebToolTestResponse.new(status_code, content_type, body)
  end

  # Recursively remove the web tools' temp directory, if any.
  def rm_rf_web_tool_temp
    rm_rf_dir(WEB_TOOL_TEMP_DIR) if Dir.exists?(WEB_TOOL_TEMP_DIR)
  end

  # Recursively remove a directory.
  def rm_rf_dir(path)
    Dir.each_child(path) do |entry|
      full = File.join(path, entry)
      if Dir.exists?(full)
        rm_rf_dir(full)
      else
        File.delete?(full)
      end
    end
    Dir.delete?(path)
  end
end
