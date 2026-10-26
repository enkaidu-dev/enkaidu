require "../../../spec_helper"
require "json"

Spectator.describe Tools::Web::HttpGetWebAsMarkdownTool do
  include WebToolSpecHelpers

  let(:renderer) { WebToolTestRenderer.new }
  let(:settings) { web_tool_settings }
  let(:tool)   { Tools::Web::HttpGetWebAsMarkdownTool.new(renderer, settings) }
  let(:runner) { Tools::Web::HttpGetWebAsMarkdownTool::Runner.new(tool) }

  # -------------------------------------------------
  # Markdown response handling
  # -------------------------------------------------

  context "handles a markdown response" do
    it "returns the content as-is with truncation false" do
      result_json = runner.receive_markdown("https://example.com", web_response("# Title\n\nHello world\n", "text/markdown"), nil)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      result_data = result[:data].as_h
      expect(result_data["url"]).to eq("https://example.com")
      expect(result_data["markdown"].as_s).to contain("# Title", "Hello world")
      expect(result_data["truncated"].as_bool).to be_false
    end

    it "truncates content larger than the maximum size" do
      big_body = "word\n" * 40_000
      result = parse_run_result(runner.receive_markdown("https://example.com", web_response(big_body, "text/markdown"), nil))

      expect(result[:success]).to be_true
      result_data = result[:data].as_h
      expect(result_data["truncated"].as_bool).to be_true
      # `each_line` strips the newline while counting, but `puts`
      # re-adds it, so the output can exceed MAX by up to a quarter.
      expect(result_data["markdown"].as_s.size.to_i64).to be_le(Tools::Web::MAX_CONTENT_SIZE * 5 // 4 + 1024)
    end

    it "saves the content to a file with its newlines intact" do
      Dir.mkdir_p(WEB_TOOL_TEMP_DIR)
      save_path = File.join(WEB_TOOL_TEMP_DIR, "page.md")
      body = "# Title\n\nLine two\n\n"
      begin
        result = parse_run_result(runner.receive_markdown("https://example.com", web_response(body, "text/markdown"), save_path))

        expect(result[:success]).to be_true
        result_data = result[:data].as_h
        expect(result_data["saved_as_file"]).to eq(save_path)
        expect(File.read(save_path)).to eq(body)
      ensure
        rm_rf_web_tool_temp
      end
    end
  end

  # -------------------------------------------------
  # HTML response handling
  # -------------------------------------------------

  context "handles an html response" do
    let(:html_body) { %(<main><h1>Title</h1><p>Hello world</p></main>) }

    it "converts the html to markdown" do
      result = parse_run_result(runner.receive_html("https://example.com", web_response(html_body, "text/html"), nil))

      expect(result[:success]).to be_true
      result_data = result[:data].as_h
      expect(result_data["markdown"].as_s).to contain("# Title", "Hello world")
      expect(result_data["truncated"].as_bool).to be_false
    end

    it "reports truncation for html that converts to more than the maximum size" do
      big_html = %(<main>#{("<p>para</p>" * 8_000)}</main>)
      result = parse_run_result(runner.receive_html("https://example.com", web_response(big_html, "text/html"), nil))

      expect(result[:success]).to be_true
      result_data = result[:data].as_h
      expect(result_data["truncated"].as_bool).to be_true
      expect(result_data["markdown"].as_s.size.to_i64).to be_le(Tools::Web::MAX_CONTENT_SIZE + 1024)
    end

    it "saves the converted markdown to a file" do
      Dir.mkdir_p(WEB_TOOL_TEMP_DIR)
      save_path = File.join(WEB_TOOL_TEMP_DIR, "page_from_html.md")
      begin
        result = parse_run_result(runner.receive_html("https://example.com", web_response(html_body, "text/html"), save_path))

        expect(result[:success]).to be_true
        expect(result[:data].as_h["saved_as_file"]).to eq(save_path)
        content = File.read(save_path)
        expect(content).to contain("# Title", "Hello world")
      ensure
        rm_rf_web_tool_temp
      end
    end
  end

  # -------------------------------------------------
  # Text response handling
  # -------------------------------------------------

  context "handles a plain-text response" do
    it "wraps the content in a code fence without a language hint" do
      result = parse_run_result(runner.receive_text("https://example.com", web_response("line one\nline two\n", "text/plain"), "text/plain", nil))

      expect(result[:success]).to be_true
      result_data = result[:data].as_h
      markdown = result_data["markdown"].as_s
      expect(markdown).to start_with("```\n")
      expect(markdown).to contain("line one", "line two")
      expect(markdown).to end_with("```\n")
      expect(result_data["truncated"].as_bool).to be_false
    end

    it "labels the code fence with the format from the content type" do
      result = parse_run_result(runner.receive_text("https://example.com", web_response("{\"a\": 1}\n", "application/json"), "application/json", nil))

      expect(result[:success]).to be_true
      markdown = result[:data].as_h["markdown"].as_s
      expect(markdown).to start_with("```json\n")
      expect(markdown).to contain("{\"a\": 1}")
      expect(markdown).to end_with("```\n")
    end

    it "uses the suffix after text/x- as the format hint" do
      result = parse_run_result(runner.receive_text("https://example.com", web_response("crystal code\n", "text/x-csharp"), "text/x-csharp", nil))

      expect(result[:success]).to be_true
      expect(result[:data].as_h["markdown"].as_s).to start_with("```csharp\n")
    end

    it "truncates the content larger than the maximum size" do
      big_body = "word\n" * 40_000
      result = parse_run_result(runner.receive_text("https://example.com", web_response(big_body, "text/plain"), "text/plain", nil))

      expect(result[:success]).to be_true
      result_data = result[:data].as_h
      expect(result_data["truncated"].as_bool).to be_true
      # `each_line` strips the newline while counting, but `puts`
      # re-adds it, so the output can exceed MAX by up to a quarter.
      expect(result_data["markdown"].as_s.size.to_i64).to be_le(Tools::Web::MAX_CONTENT_SIZE * 5 // 4 + 1024)
    end

    it "saves the fenced content to a file" do
      Dir.mkdir_p(WEB_TOOL_TEMP_DIR)
      save_path = File.join(WEB_TOOL_TEMP_DIR, "page_text.md")
      begin
        result = parse_run_result(runner.receive_text("https://example.com", web_response("{\"a\": 1}\n", "application/json"), "application/json", save_path))

        expect(result[:success]).to be_true
        content = File.read(save_path)
        expect(content).to start_with("```json\n")
        expect(content).to contain("{\"a\": 1}\n")
        expect(content).to end_with("```")
      ensure
        rm_rf_web_tool_temp
      end
    end
  end

  # -------------------------------------------------
  # execute: argument validation
  # -------------------------------------------------

  context "when url is not provided" do
    it "returns an error" do
      result = parse_run_result(run_runner(runner, {
        "reason" => "Testing missing url.",
      }))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/The required URL was not specified/)
    end
  end

  # -------------------------------------------------
  # execute: save path validation
  # -------------------------------------------------

  context "when the save path is outside the current directory" do
    it "returns an error before fetching" do
      result = parse_run_result(run_runner(runner, {
        "url"          => "https://example.com",
        "reason"       => "Testing outside path.",
        "save_as_file" => File.expand_path("/tmp/enkaidu_http_web_test_outside.md"),
      }))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/is not allowed/)
    end
  end

  context "when the save target already exists without overwrite" do
    before do
      Dir.mkdir_p(WEB_TOOL_TEMP_DIR)
      File.write(File.join(WEB_TOOL_TEMP_DIR, "existing.md"), "old content")
    end
    after { rm_rf_web_tool_temp }

    it "returns an error" do
      result = parse_run_result(run_runner(runner, {
        "url"          => "https://example.com",
        "reason"       => "Testing save conflict.",
        "save_as_file" => "spec/tmp_http_web_test/existing.md",
      }))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/already exists/)
    end
  end

  context "when the save target already exists with overwrite" do
    before do
      Dir.mkdir_p(WEB_TOOL_TEMP_DIR)
      File.write(File.join(WEB_TOOL_TEMP_DIR, "existing.md"), "old content")
    end
    after { rm_rf_web_tool_temp }

    it "passes validation and proceeds to fetch" do
      # No server listens on this port, so the fetch itself fails;
      # the point is that the save validation does not error first.
      result = parse_run_result(run_runner(runner, {
        "url"          => "http://127.0.0.1:1/x",
        "reason"       => "Testing overwrite.",
        "save_as_file" => "spec/tmp_http_web_test/existing.md",
        "overwrite"    => true,
      }))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to_not match(/already exists/)
      expect(result[:error_msg]).to match(/An error occurred while making the HTTP request/)
    end
  end

  context "when overwriting a file inside the deleted-files folder" do
    let(:save_path) { File.join(WEB_TOOL_TEMP_DIR, ".deleted_files", "gone.md") }

    before do
      Dir.mkdir_p(File.dirname(save_path))
      File.write(save_path, "old")
    end
    after { rm_rf_web_tool_temp }

    it "returns an error" do
      result = parse_run_result(run_runner(runner, {
        "url"          => "https://example.com",
        "reason"       => "Testing deleted-files protection.",
        "save_as_file" => save_path,
        "overwrite"    => true,
      }))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/Cannot overwrite files in the `\.deleted_files\/` folder/)
    end
  end

  # -------------------------------------------------
  # execute: host policy
  # -------------------------------------------------

  context "when the host is on the denied list" do
    let(:settings) { web_tool_settings(denied_hosts: ["127.0.0.1"]) }

    it "returns an error with a suggestion without prompting the user" do
      result = parse_run_result(run_runner(runner, {
        "url"    => "http://127.0.0.1:1/x",
        "reason" => "Testing denied host.",
      }))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/is not a host this tool may fetch/)
      expect(result[:data].as_h["suggestion"].as_s).to contain("ask the operator to allow this one")
      expect(renderer.permission_questions).to be_empty
    end
  end

  context "when the host is unknown and the user denies the permission" do
    let(:settings) { web_tool_settings(allowed_hosts: [] of String) }

    it "returns an error and remembers the denial when the user says remember" do
      renderer.permission_response = Enkaidu::SessionRenderer::Permission.new(approved: false, remember: true)
      first = parse_run_result(run_runner(runner, {
        "url"    => "http://127.0.0.1:1/x",
        "reason" => "Testing permission denial.",
      }))

      expect(first[:success]).to be_false
      expect(first[:error_msg]).to match(/is not a host this tool may fetch/)
      expect(renderer.permission_questions).to contain("http://127.0.0.1:1/x")

      # The denial was remembered, so the second fetch errors without a new prompt.
      second = parse_run_result(run_runner(runner, {
        "url"    => "http://127.0.0.1:1/x",
        "reason" => "Testing remembered denial.",
      }))
      expect(second[:success]).to be_false
      expect(second[:error_msg]).to match(/is not a host this tool may fetch/)
      expect(renderer.permission_questions.size).to eq(1)
    end
  end

  context "when the host is unknown and the user approves the permission" do
    let(:settings) { web_tool_settings(allowed_hosts: [] of String) }

    it "proceeds to fetch and stops asking when the user remembers the approval" do
      renderer.permission_response = Enkaidu::SessionRenderer::Permission.new(approved: true, remember: true)
      first = parse_run_result(run_runner(runner, {
        "url"    => "http://127.0.0.1:1/x",
        "reason" => "Testing permission approval.",
      }))

      # No server listens on this port, so the fetch fails with a
      # connection error; the point is that the permission was honored.
      expect(first[:success]).to be_false
      expect(first[:error_msg]).to match(/An error occurred while making the HTTP request/)
      expect(renderer.permission_questions).to contain("http://127.0.0.1:1/x")

      # The approval was remembered, so the second fetch proceeds without a new prompt.
      second = parse_run_result(run_runner(runner, {
        "url"    => "http://127.0.0.1:1/x",
        "reason" => "Testing remembered approval.",
      }))
      expect(second[:success]).to be_false
      expect(second[:error_msg]).to match(/An error occurred while making the HTTP request/)
      expect(renderer.permission_questions.size).to eq(1)
    end
  end
end
