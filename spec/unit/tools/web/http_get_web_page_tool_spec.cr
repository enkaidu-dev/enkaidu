require "../../../spec_helper"
require "json"

Spectator.describe Tools::Web::HttpGetWebPageTool do
  include WebToolSpecHelpers

  let(:renderer) { WebToolTestRenderer.new }
  let(:settings) { web_tool_settings }
  let(:tool)   { Tools::Web::HttpGetWebPageTool.new(renderer, settings) }
  let(:runner) { Tools::Web::HttpGetWebPageTool::Runner.new(tool) }

  def success_body(content_type, content, preserve_source = false)
    result = parse_run_result(runner.success_response(content_type, content, preserve_source))
    expect(result[:success]).to be_true
    result[:data].as_h["body"].as_s
  end

  # -------------------------------------------------
  # success_response: content reduction
  # -------------------------------------------------

  context "with preserve_source" do
    it "returns the content as-is even when it is json" do
      raw = %(  {\n    "a": 1,\n\n    "b": 2\n  })
      body = success_body("application/json", raw, true)

      expect(body).to eq(raw)
    end

    it "returns the content as-is even when it is html" do
      raw = %(  <html>\n    <body class="main">\n      <h1>Title</h1>\n    </body>\n  </html>)
      body = success_body("text/html", raw, true)

      expect(body).to eq(raw)
    end
  end

  context "reducing json content" do
    it "strips line indents and coalesces line break runs" do
      raw = %(  {\n    "a": 1,\n\n    "b": 2\n  })
      body = success_body("application/json", raw)

      expect(body).to eq("{\n\"a\": 1,\n\"b\": 2\n}")
    end
  end

  context "reducing xml content" do
    it "strips line indents and coalesces line break runs" do
      raw = %(  <root>\n    <item>1</item>\n\n    <item>2</item>\n  </root>)
      body = success_body("application/xml", raw)

      expect(body).to eq("<root>\n<item>1</item>\n<item>2</item>\n</root>")
    end
  end

  context "reducing html content" do
    it "removes script and style elements and class attributes" do
      raw = <<-HTML
        <html>
        <body class="main">
        <h1>Title</h1>
        <script>var x = 1;</script>
        <p class='para'>Hello world</p>
        </body>
        </html>
        HTML

      body = success_body("text/html", raw)

      expect(body).to_not contain("<script>", "var x = 1;", "class=")
      # The space before the removed attribute is left behind.
      expect(body).to contain("<body >", "<h1>Title</h1>", "<p >Hello world</p>")
    end

    it "removes a single-line head element" do
      raw = "<html><head><title>Title</title></head><body><h1>Title</h1></body></html>"

      body = success_body("text/html", raw)

      expect(body).to_not contain("<head>", "<title>")
      expect(body).to contain("<body><h1>Title</h1></body></html>")
    end

    it "strips line indents and coalesces line break runs" do
      raw = %(  <html>\n    <body>\n\n      <h1>Title</h1>\n    </body>\n  </html>)

      body = success_body("text/html", raw)

      expect(body).to eq("<html>\n<body>\n<h1>Title</h1>\n</body>\n</html>")
    end
  end

  context "with a content type that has no reduction rules" do
    it "returns the content unchanged" do
      raw = %(  spaced\n\n\ntext)

      body = success_body("text/plain", raw)

      expect(body).to eq(raw)
    end
  end

  context "includes the content type in the response" do
    it "returns it alongside the body" do
      result = parse_run_result(runner.success_response("application/json", "{}", true))

      expect(result[:success]).to be_true
      result_data = result[:data].as_h
      expect(result_data["content_type"]).to eq("application/json")
      expect(result_data["body"].as_s).to eq("{}")
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
      expect(first[:error_msg]).to match(/is not one of the hosts this tool may fetch/)
      expect(renderer.permission_questions).to contain("http://127.0.0.1:1/x")

      # The denial was remembered, so the second fetch is denied
      # outright without a new prompt.
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
