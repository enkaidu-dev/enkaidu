require "../../../spec_helper"
require "json"

Spectator.describe Tools::TextEditing::ReadTextFileTool do
  let(:temp_dir) { "spec/tmp_test" }
  let(:file_path) { File.join(temp_dir, "sample.txt") }
  let(:runner) { Tools::TextEditing::ReadTextFileTool::Runner.new }

  before { Dir.mkdir_p(temp_dir) }
  after do
    File.delete?(file_path)
    Dir.delete?(temp_dir)
  end

  # ---- Successful read scenarios ----
  context "reads the entire file without line numbers" do
    let(:original_content) { "line 1\nline 2\nline 3\n" }
    before { File.write(file_path, original_content) }

    it "returns the file content as a string" do
      args = {
        "file_path"            => file_path,
        "include_line_numbers" => false,
        "line_range"           => [1, -1],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil
      expect(result["content"]?).to eq(original_content)
    end
  end

  context "reads the entire file with line numbers" do
    let(:original_content) { "first\nsecond\nthird\n" }
    before { File.write(file_path, original_content) }

    it "includes line numbers in output when requested" do
      args = {
        "file_path"            => file_path,
        "include_line_numbers" => true,
        "line_range"           => [1, -1],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil
      lines = result["content"].as_s.split("\n")
      expect(lines.size).to eq(4)
      expect(lines[0]).to match(/^\s*1\tfirst/)
      expect(lines[1]).to match(/^\s*2\tsecond/)
      expect(lines[2]).to match(/^\s*3\tthird/)
    end
  end

  context "reads a specific line range (e.g., lines 2-3)" do
    let(:original_content) { "line 1\nline 2\nline 3\nline 4\n" }
    before { File.write(file_path, original_content) }

    it "returns only the specified lines" do
      args = {
        "file_path"            => file_path,
        "include_line_numbers" => false,
        "line_range"           => [2, 3],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil
      expect(result["content"].as_s).to eq("line 2\nline 3\n")
    end
  end

  context "reads lines with line numbers in a range" do
    let(:original_content) { "A\nB\nC\nD\n" }
    before { File.write(file_path, original_content) }

    it "includes line numbers for the specified range" do
      args = {
        "file_path"            => file_path,
        "include_line_numbers" => true,
        "line_range"           => [2, 4],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil
      lines = result["content"].as_s.split("\n")
      expect(lines.size).to eq(3 + 1)
      expect(lines[0]).to match(/^\s*2\tB/)
      expect(lines[1]).to match(/^\s*3\tC/)
      expect(lines[2]).to match(/^\s*4\tD/)
    end
  end

  # ---- Error handling scenarios ----
  context "fails when file_path is not provided" do
    it "returns an error" do
      args = {
        "include_line_numbers" => false,
        "line_range"           => [1, -1],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]).not_to be_nil
      expect(result["error"].as_s).to match(/The required `file_path` was not specified/)
    end
  end

  context "fails when the specified file does not exist" do
    it "returns an error" do
      args = {
        "file_path"            => "nonexistent.txt",
        "include_line_numbers" => false,
        "line_range"           => [1, -1],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]).not_to be_nil
      expect(result["error"]).to match(/The specified file 'nonexistent.txt' does not exist/)
    end
  end

  context "fails when the path points outside the allowed directory" do
    let(:outside_path) { File.tempname("_outside.txt") }

    it "returns an error" do
      args = {
        "file_path"            => outside_path,
        "include_line_numbers" => false,
        "line_range"           => [1, -1],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]).not_to be_nil
      expect(result["error"]).to match(/Access to the specified path '#{Regex.escape(outside_path)}' is not allowed/)
    end
  end

  context "fails when an invalid line_range format is given" do
    let(:original_content) { "content" }
    before { File.write(file_path, original_content) }

    it "returns an error" do
      args = {
        "file_path"            => file_path,
        "include_line_numbers" => false,
        "line_range"           => "invalid", # not an array
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]).not_to be_nil
      expect(result["error"]).to match(/The `line_range` must be an array with two integers/)
    end
  end

  context "fails when line_range contains non-integer values" do
    let(:original_content) { "content" }
    before { File.write(file_path, original_content) }

    it "returns an error" do
      args = {
        "file_path"            => file_path,
        "include_line_numbers" => false,
        "line_range"           => [1, "two"],
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]).not_to be_nil
      expect(result["error"]).to match(/The `line_range` must be an array with two integers/)
    end
  end
end
