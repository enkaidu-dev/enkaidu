require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Session renderer callbacks smoke test" do
  let(:renderer) { EnkaiduWiretapTestRenderer.new }

  describe "basic message callbacks" do
    it "info_with" do
      renderer.info_with("hello")
      renderer.info_with("hello", "help text", true)
      expect(renderer.info_messages).to contain("hello")
    end

    it "warning_with" do
      renderer.warning_with("warn")
      renderer.warning_with("warn", "help", true)
      expect(renderer.warnings).to contain("warn")
    end

    it "error_with" do
      renderer.error_with("boom")
      renderer.error_with("boom", "help", true)
      expect(renderer.errors).to contain("boom")
    end

    it "respond_with" do
      renderer.respond_with("response")
      renderer.respond_with("response", "help", true)
      expect(renderer.responses).to contain("response")
    end
  end

  describe "user query callbacks" do
    it "user_query_text" do
      renderer.user_query_text("what is up?")
      renderer.user_query_text("what is up?", true)
    end

    it "user_query_image_url" do
      renderer.user_query_image_url("https://example.com/img.png")
    end
  end

  describe "user interaction callbacks" do
    it "user_permission_question returns a Permission" do
      result = renderer.user_permission_question("desc", "subject")
      expect(result).to be_a(Enkaidu::SessionRenderer::Permission)
      expect(result.approved?).to be_false
      expect(result.remember?).to be_false
    end

    it "user_permission_question accepts array subject and optional params" do
      banner = Enkaidu::SessionRenderer::Banner.new(true, "safe")
      result = renderer.user_permission_question("desc", ["a", "b"], "caution", banner)
      expect(result).to be_a(Enkaidu::SessionRenderer::Permission)
    end

    it "user_confirm_security_question? returns true" do
      result = renderer.user_confirm_security_question?("desc", "subject")
      expect(result).to be_true
    end

    it "user_confirm_security_question? accepts optional banner" do
      result = renderer.user_confirm_security_question?("desc", "subject", {safe: true, message: "banner"})
      expect(result).to be_true
    end
  end

  describe "time and session callbacks" do
    it "time_elapsed" do
      renderer.time_elapsed(2.seconds)
      renderer.time_elapsed(2.seconds, "label")
    end

    it "session_pushed" do
      renderer.session_pushed(1, true, true, true)
    end

    it "session_popped" do
      renderer.session_popped(1)
    end

    it "session_stack_new" do
      renderer.session_stack_new("my_stack")
    end

    it "session_stack_changed" do
      renderer.session_stack_changed("my_stack")
    end

    # session_reset requires two Enkaidu::Session instances; skipped.
  end

  describe "LLM callbacks" do
    it "llm_tool_call records the tool name" do
      renderer.llm_tool_call("my_tool", JSON.parse(%({"a":1})))
      expect(renderer.tool_calls).to contain("my_tool")
    end

    it "llm_text" do
      renderer.llm_text("some text", false)
      renderer.llm_text("some text", false, true)
      renderer.llm_text("some text", false, false, true)
      renderer.llm_text("reasoning", true)
    end

    it "llm_text_block" do
      renderer.llm_text_block("block text", false)
      renderer.llm_text_block("reasoning block", true)
    end

    it "llm_image_url" do
      renderer.llm_image_url("https://example.com/out.png")
    end

    it "llm_error" do
      renderer.llm_error(RuntimeError.new("LLM exploded"))
      renderer.llm_error(RuntimeError.new("LLM exploded"), "fallback message")
    end
  end

  describe "MCP callbacks" do
    it "mcp_initialized" do
      renderer.mcp_initialized("https://mcp.example.com")
    end

    it "mcp_tools_found" do
      renderer.mcp_tools_found(3)
    end

    it "mcp_tool_ready" do
      renderer.mcp_tool_ready("some_function_name")
    end

    it "mcp_prompts_found" do
      renderer.mcp_prompts_found(2)
    end

    it "mcp_prompt_ready" do
      renderer.mcp_prompt_ready("some_prompt_name")
    end

    it "mcp_calling_tool" do
      renderer.mcp_calling_tool("https://mcp.example.com", "tool_name", JSON.parse(%({"x":1})))
    end

    it "mcp_calling_tool_result" do
      renderer.mcp_calling_tool_result("https://mcp.example.com", "tool_name", JSON.parse(%({"ok":true})))
    end

    it "mcp_error" do
      renderer.mcp_error(RuntimeError.new("MCP failure"))
    end

    # mcp_prompt_ask_input requires a MCPPrompt instance (MCPC::HttpConnection); skipped.
    # user_prompt_ask_input requires a TemplatePrompt instance (Session); skipped.
  end
end
