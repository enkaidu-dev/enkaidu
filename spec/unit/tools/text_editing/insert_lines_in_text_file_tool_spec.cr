require "../../../spec_helper"
require "json"

Spectator.describe Tools::TextEditing::InsertLinesInTextFileTool do
  # fixtures
  let(:temp_dir) { "spec/tmp_test" }
  let(:file_path) { File.join(temp_dir, "sample.txt") }
  let(:runner) { Tools::TextEditing::InsertLinesInTextFileTool::Runner.new }

  before { Dir.mkdir_p(temp_dir) }
  after do
    File.delete?(file_path)
    Dir.delete?(temp_dir)
  end

  # -------------------------------------------------
  # Successful insertion scenarios
  # -------------------------------------------------

  context "inserts text at the beginning of the file (line 0)" do
    let(:original_content) { "first line\nsecond line\nthird line\n" }
    let(:insert_text) { "INSERTED AT START\n" }

    before do
      File.write(file_path, original_content)
    end

    it "succeeds and updates the file correctly" do
      args = {
        "file_path"   => file_path,
        "insert_line" => 0,
        "insert_text" => insert_text,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      # no error should be present
      expect(result["error"]?).to be_nil

      # verify file content
      revised_content = File.read(file_path)
      expect(revised_content).to eq("INSERTED AT START\nfirst line\nsecond line\nthird line\n")
    end
  end

  context "inserts text after a specific line (e.g., after line 1)" do
    let(:original_content) { " lineA\n lineB\n lineC\n" }
    let(:insert_text) { " NEW CONTENT AFTER LINE 1\n" }

    before do
      File.write(file_path, original_content)
    end

    it "succeeds and places the new text after line 1" do
      args = {
        "file_path"   => file_path,
        "insert_line" => 1,
        "insert_text" => insert_text,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil

      revised_content = File.read(file_path)
      expect(revised_content).to eq(" lineA\n NEW CONTENT AFTER LINE 1\n lineB\n lineC\n")
    end
  end

  context "appends text at the end of the file (line -1)" do
    let(:original_content) { "START\nMIDDLE\n" }
    let(:insert_text) { "\nAPPEND TEXT" }

    before do
      File.write(file_path, original_content)
    end

    it "succeeds and appends the text at the end" do
      args = {
        "file_path"   => file_path,
        "insert_line" => -1,
        "insert_text" => insert_text,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil

      revised_content = File.read(file_path)
      expect(revised_content).to eq("START\nMIDDLE\n\nAPPEND TEXT")
    end
  end

  # -------------------------------------------------
  # Error handling scenarios
  # -------------------------------------------------

  context "fails when file_path is not provided" do
    it "returns an error" do
      args = {
        "insert_line" => 0,
        "insert_text" => "anything", # file_path missing
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The required `file_path` was not specified/)
    end
  end

  context "fails when insert_line is not provided" do
    let(:file_path) { File.join(temp_dir, "exist.txt") }
    let(:original_content) { "content" }
    before do
      File.write(file_path, original_content)
      Dir.mkdir_p(temp_dir)
    end

    it "returns an error" do
      args = {
        "file_path"   => file_path,
        "insert_text" => "new text", # insert_line missing
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The required `insert_line` was not specified/)
    end
  end

  context "fails when insert_text is not provided" do
    let(:file_path) { File.join(temp_dir, "exist.txt") }
    let(:original_content) { "content" }
    before do
      File.write(file_path, original_content)
      Dir.mkdir_p(temp_dir)
    end

    it "returns an error" do
      args = {
        "file_path"   => file_path,
        "insert_line" => 0,
        # insert_text missing
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The required `insert_text` was not specified/)
    end
  end

  context "fails when the target file does not exist" do
    it "returns an error" do
      args = {
        "file_path"   => "nonexistent.txt",
        "insert_line" => 0,
        "insert_text" => "anything",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The specified file 'nonexistent.txt' does not exist/)
    end
  end

  context "fails when the specified path is outside the current directory" do
    let(:outside_path) { File.tempname("_outside.txt") }

    it "returns an error" do
      args = {
        "file_path"   => outside_path,
        "insert_line" => 0,
        "insert_text" => "test",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The specified path '#{Regex.escape(outside_path)}' is not allowed/)
    end
  end

  context "fails when the file_path points to a non-file (e.g., a directory)" do
    let(:dir_path) { File.join(temp_dir, "subdir") }

    before { Dir.mkdir_p(dir_path) }
    after { Dir.delete?(dir_path) }

    it "returns an error" do
      args = {
        "file_path"   => dir_path,
        "insert_line" => 0,
        "insert_text" => "test",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The specified file '#{Regex.escape(dir_path)}' does not exist or is not a file/)
    end
  end

  context "fails when insert_line is not an integer" do
    let(:file_path) { File.join(temp_dir, "exist.txt") }
    let(:original_content) { "content" }
    before do
      File.write(file_path, original_content)
      Dir.mkdir_p(temp_dir)
    end

    it "returns an error" do
      args = {
        "file_path"   => file_path,
        "insert_line" => "invalid",
        "insert_text" => "new",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The required `insert_line` was not specified/)
    end
  end
end
