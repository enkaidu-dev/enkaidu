require "../../../spec_helper"
require "json"

Spectator.describe Tools::TextEditing::WriteTextFileTool do
  # fixtures
  let(:temp_dir) { "spec/tmp_write_test" }
  let(:runner) { Tools::TextEditing::WriteTextFileTool::Runner.new }

  # Recursively delete a directory for cleanup
  def rm_rf(path)
    return unless path.starts_with?("spec/tmp") # guardrail
    if Dir.exists?(path)
      Dir.each_child(path) do |entry|
        full = File.join(path, entry)
        if Dir.exists?(full)
          rm_rf(full)
        else
          File.delete?(full)
        end
      end
      Dir.delete?(path)
    end
  end

  before { Dir.mkdir_p(temp_dir) }
  after { rm_rf(temp_dir) if Dir.exists?(temp_dir) }

  # -------------------------------------------------
  # Successful write scenarios
  # -------------------------------------------------

  context "creates a new file with the given content" do
    let(:file_path) { File.join(temp_dir, "new_file.txt") }
    let(:content) { "Hello, world!" }

    it "succeeds and writes the content correctly" do
      args = {
        "file_path" => file_path,
        "content"   => content,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil
      expect(File.read(file_path)).to eq(content)
      expect(result["message"]).to match(/created successfully/)
    end
  end

  context "creates a file in a nested sub-directory if needed" do
    let(:nested_path) { File.join(temp_dir, "a", "b", "c", "nested.txt") }
    let(:content) { "nested content" }

    it "creates directories and writes the file" do
      args = {
        "file_path" => nested_path,
        "content"   => content,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil
      expect(File.read(nested_path)).to eq(content)
    end
  end

  context "overwrites an existing file when overwrite is true" do
    let(:file_path) { File.join(temp_dir, "overwrite_me.txt") }
    let(:original_content) { "original" }
    let(:new_content) { "overwritten" }

    before { File.write(file_path, original_content) }

    it "succeeds and replaces the old content" do
      args = {
        "file_path" => file_path,
        "content"   => new_content,
        "overwrite" => true,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"]?).to be_nil
      expect(File.read(file_path)).to eq(new_content)
      expect(result["message"]).to match(/over-written successfully/)
    end
  end

  # -------------------------------------------------
  # Error handling scenarios
  # -------------------------------------------------

  context "fails when file_path is not provided" do
    it "returns an error" do
      args = {
        "content" => "some content",
        # file_path missing
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The required file_path was not specified/)
    end
  end

  context "fails when content is not provided" do
    let(:file_path) { File.join(temp_dir, "no_content.txt") }

    it "returns an error" do
      args = {
        "file_path" => file_path,
        # content missing
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/The required content was not specified/)
    end
  end

  context "fails when the file already exists and overwrite is false" do
    let(:file_path) { File.join(temp_dir, "exists.txt") }
    let(:original_content) { "I am here" }

    before { File.write(file_path, original_content) }

    it "returns an error without modifying the file" do
      args = {
        "file_path" => file_path,
        "content"   => "new content",
        "overwrite" => false,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/already exists/)
      expect(File.read(file_path)).to eq(original_content)
    end
  end

  context "fails when overwrite is false (default) and file exists" do
    let(:file_path) { File.join(temp_dir, "defaults_to_no_overwrite.txt") }
    let(:original_content) { "existing" }

    before { File.write(file_path, original_content) }

    it "returns an error without overwrite param" do
      args = {
        "file_path" => file_path,
        "content"   => "new content",
        # overwrite not provided, defaults to false
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/already exists/)
    end
  end

  context "fails when the specified path is outside the current directory" do
    let(:outside_path) { File.tempname("_outside.txt") }

    it "returns an error" do
      args = {
        "file_path" => outside_path,
        "content"   => "test",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/is not allowed/)
    end
  end

  context "fails when trying to overwrite a file in the deleted files folder" do
    let(:deleted_path) { File.join(".deleted_files", "old_file.txt") }
    let(:original_content) { "to be recovered" }

    before do
      Dir.mkdir_p(".deleted_files")
      File.write(deleted_path, original_content)
    end

    after { rm_rf(".deleted_files") }

    it "returns an error even with overwrite=true" do
      args = {
        "file_path" => ".deleted_files/old_file.txt",
        "content"   => "new content",
        "overwrite" => true,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
      expect(result["error"]).to match(/Cannot overwrite files in the/)
      expect(File.read(deleted_path)).to eq(original_content)
    end
  end

  context "fails when the file_path resolves to a directory" do
    let(:dir_path) { File.join(temp_dir, "a_dir") }

    before { Dir.mkdir_p(dir_path) }

    it "returns an error because you cannot write to a directory" do
      args = {
        "file_path" => dir_path,
        "content"   => "some content",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
    end
  end

  context "fails when the parent directory cannot be created" do
    # Attempt to write into a path where parent dir creation would fail
    let(:restricted_path) { "/some/restricted/path/file.txt" }

    it "returns an error for write failures" do
      args = {
        "file_path" => restricted_path,
        "content"   => "content",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key("error")
    end
  end
end
