require "../../../spec_helper"
require "json"

Spectator.describe Tools::TextEditing::ReplaceTextInTextFileTool do
  # -----------------------------------------------------------------
  # Shared test fixtures
  # -----------------------------------------------------------------
  let(:temp_dir) { "spec/tmp_test" }
  let(:file_path) { File.join(temp_dir, "sample.txt") }

  before { Dir.mkdir_p(temp_dir) }
  after { File.delete?(file_path) }

  let(:runner) { Tools::TextEditing::ReplaceTextInTextFileTool::Runner.new }

  # -----------------------------------------------------------------
  # Successful replacement scenarios
  # -----------------------------------------------------------------
  context "replaces the first occurrence when `multiple` is false" do
    let(:content) { "first line old text second line old text" }
    before { File.write(file_path, content) }

    it "succeeds and reports a single replacement" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
        "multiple"  => false,
      }.to_json))
      result = JSON.parse(result_json)

      expect(result["replacements"].as_i).to be 1
      expect(result["new_content"].as_s).to eq "first line new text second line old text"
    end
  end

  context "replaces all occurrences when `multiple` is true" do
    let(:content) { "first line old text second line old text" }
    before { File.write(file_path, content) }

    it "succeeds and reports multiple replacements" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
        "multiple"  => true,
      }.to_json))
      result = JSON.parse(result_json)

      expect(result["replacements"].as_i).to be 2
      expect(result["new_content"].as_s).to eq "first line new text second line new text"
    end
  end

  # -----------------------------------------------------------------
  # Error handling scenarios
  # -----------------------------------------------------------------
  context "fails when the target file does not exist" do
    it "returns an error" do
      result_json = runner.execute(JSON.parse({
        "file_path" => "nonexistent.txt",
        "old_str"   => "any",
        "new_str"   => "thing",
        "multiple"  => false,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "does not exist"
    end
  end

  context "fails when the old string is not found" do
    let(:content) { "no old here" }
    before { File.write(file_path, content) }

    it "returns an error" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "missing",
        "new_str"   => "something",
        "multiple"  => false,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "Unable to find old string"
    end
  end

  context "rejects paths outside the current directory" do
    let(:file_path) { File.tempname("_outside.txt") }

    it "returns an error" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "test",
        "new_str"   => "changed",
        "multiple"  => false,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "not allowed"
    end
  end
end
