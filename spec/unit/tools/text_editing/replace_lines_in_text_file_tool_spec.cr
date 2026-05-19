require "../../../spec_helper"
require "json"

Spectator.describe Tools::TextEditing::ReplaceLinesInTextFileTool do
  # -----------------------------------------------------------------
  # Shared test fixtures
  # -----------------------------------------------------------------
  let(:temp_dir) { "spec/tmp_test" }
  let(:file_path) { File.join(temp_dir, "sample.txt") }

  before { Dir.mkdir_p(temp_dir) }
  after do
    File.delete?(file_path)
    Dir.delete?(temp_dir)
  end

  let(:runner) { Tools::TextEditing::ReplaceLinesInTextFileTool::Runner.new }

  # -----------------------------------------------------------------
  # Successful replacement scenarios
  # -----------------------------------------------------------------

  context "replaces a single line" do
    let(:content) { "first line old text\nsecond line old text\nthird line" }
    before { File.write(file_path, content) }

    it "succeeds and reports replacement of one line" do
      args = {
        "file_path"  => file_path,
        "line_range" => [2, 2],
        "new_str"    => "new line",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be nil
      expect(result["status"].as_s).to eq "Success"
      expect(result["message"].as_s).to match(/range.+2[^0-9]+2/)

      # Verify file content after replacement
      revised_content = File.read(file_path)
      expect(revised_content).to eq "first line old text\nnew line\nthird line"
    end
  end

  context "replaces a range of lines" do
    let(:content) { "line1\nline2-old\nline3-old\nline4" }
    before { File.write(file_path, content) }

    it "replaces lines 2 to 3 with new content" do
      args = {
        "file_path"  => file_path,
        "line_range" => [2, 3],
        "new_str"    => "replaced line A\nreplaced line B",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["status"].as_s).to eq "Success"
      expect(result["message"].as_s).to contain("Successfully replaced")
      expect(result["message"].as_s).to match(/range.+2[^0-9]+3/)

      revised_content = File.read(file_path)
      expect(revised_content).to eq "line1\nreplaced line A\nreplaced line B\nline4"
    end
  end

  context "replaces all lines when range ends at -1" do
    let(:content) { "first\nsecond\nthird" }
    before { File.write(file_path, content) }

    it "replaces all lines with new content" do
      args = {
        "file_path"  => file_path,
        "line_range" => [1, -1],
        "new_str"    => "NEW ENTIRE FILE",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["status"].as_s).to eq "Success"
      expect(result["message"].as_s).to match(/range.+1[^0-9]+\-1/)

      revised_content = File.read(file_path)
      expect(revised_content).to eq "NEW ENTIRE FILE"
    end
  end

  # -----------------------------------------------------------------
  # Error handling scenarios
  # -----------------------------------------------------------------

  context "fails when the target file does not exist" do
    it "returns an error" do
      args = {
        "file_path"  => "nonexistent.txt",
        "line_range" => [1, 1],
        "new_str"    => "anything",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "does not exist"
    end
  end

  context "fails when the line_range is invalid (start > end)" do
    let(:content) { "only line" }
    before { File.write(file_path, content) }

    it "returns an error" do
      args = {
        "file_path"  => file_path,
        "line_range" => [3, 2], # start > end
        "new_str"    => "new",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "invalid"
    end
  end

  context "fails when line_range contains non-integer values" do
    let(:content) { "line" }
    before { File.write(file_path, content) }

    it "returns an error" do
      args = {
        "file_path"  => file_path,
        "line_range" => ["a", "b"], # not integers
        "new_str"    => "new",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "must be an array with two integers"
    end
  end

  context "fails when the specified file is outside the current directory" do
    let(:file_path) { File.tempname("_outside.txt") }

    it "returns an error" do
      args = {
        "file_path"  => file_path,
        "line_range" => [1, 1],
        "new_str"    => "new",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "not allowed"
    end
  end

  context "fails when `new_str` is not provided" do
    let(:content) { "line1\nline2" }
    before { File.write(file_path, content) }

    it "returns an error" do
      args = {
        "file_path"  => file_path,
        "line_range" => [1, 2],
        "new_str"    => nil,
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "not specified"
    end
  end
end
