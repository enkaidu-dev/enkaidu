require "../../spec_helper"

Spectator.describe HtmlToMarkdown do
  let(html) {
    <<-HTMLSRC_
    <!doctype html>
    <html>
    <head>
      <script src="my.js"></script>
      <style></style>
    </head>
    <body>
      Hello
    </body>
    </html>
    HTMLSRC_
  }
  let(html_io) { IO::Memory.new(html) }
  let(markdown) { HtmlToMarkdown.translate(html_io) }

  describe "#translate" do
    context "just hello" do
      it "OK" do
        expect(markdown.strip).to eq("Hello")
      end
    end

    context "ordered list" do
      let(expected_markdown) {
        <<-MD_
        1. One
        1. Two
        MD_
      }
      context "(without end list item tag)" do
        let(html) { "<ol><li>One<li>Two</ol>" }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
      context "(with closing list item tags)" do
        let(html) { "<ol><li>One</li><li>Two</li></ol>" }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
    end

    context "unordered list" do
      let(expected_markdown) {
        <<-MD_
        * One
        * Two
        MD_
      }
      context "(without end list item tag)" do
        let(html) { "<ul><li>One<li>Two</ul>" }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
      context "(with closing list item tags)" do
        let(html) { "<ul><li>One</li><li>Two</li></ul>" }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
    end

    context "inline formatting" do
      let(expected_markdown) { "Some **bold** and _italics_ text" }
      context "(with <b> and <i>)" do
        let(html) { "Some <b>bold</b> and <i>italics</i> text" }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
      context "(with <strong> and <em>)" do
        let(html) { "Some <strong>bold</strong> and <em>italics</em> text" }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
    end

    context "headings" do
      context "(three levels)" do
        let(expected_markdown) {
          <<-MD_
          # Title


          ## Section


          ### Sub-section
          MD_
        }
        let(html) {
          <<-HTMLSRC_
          <html>
          <body>
            <h1>Title</h1>
            <h2>Section</h2>
            <h3>Sub-section</h3>
          </body>
          </html>
          HTMLSRC_
        }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
      context "(with section text)" do
        let(expected_markdown) {
          <<-MD_
          # Title

          Welcome.

          ## Section

          Don't forget to do this.

          ### Sub-section

          Here's an example.
          MD_
        }
        let(html) {
          <<-HTMLSRC_
          <html>
          <body>
            <h1>Title</h1>
            Welcome.
            <h2>Section</h2>
            Don't forget to do this.
            <h3>Sub-section</h3>
            Here's an example.
          </body>
          </html>
          HTMLSRC_
        }
        it "OK" do
          expect(markdown.strip).to eq(expected_markdown)
        end
      end
    end
  end
end
