require "../../../spec_helper"
require "json"

Spectator.describe Tools::FileManagement::DeleteFileTool do
  include FileToolSpecHelpers

  let(:temp_dir) { "spec/tmp_delete_test" }
  let(:runner)   { Tools::FileManagement::DeleteFileTool::Runner.new }

  before { Dir.mkdir_p(temp_dir) }
  after do
    rm_rf_dir(temp_dir) if Dir.exists?(temp_dir)
    rm_rf_dir(".deleted_files") if Dir.exists?(".deleted_files")
  end

  # Extract the target path from the success message.
  def extract_target_path(message)
    message[/to '([^']+)'/, 1]
  end

  # -------------------------------------------------
  # Successful deletion scenarios
  # -------------------------------------------------

  context "deletes a file within a sub-directory" do
    let(:sub_dir)   { File.join(temp_dir, "sub") }
    let(:file_path) { File.join(sub_dir, "victim.txt") }

    before do
      Dir.mkdir_p(sub_dir)
      File.write(file_path, "doomed content")
    end

    it "moves the file into the .deleted_files folder preserving the structure" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path)))

      expect(result[:success]).to be_true
      expect(result[:error_msg]).to be_nil

      message = result[:data].as_h["message"].as_s
      expect(message).to contain("File deleted successfully")

      expect(File.exists?(file_path)).to be_false

      target_path = extract_target_path(message).as(String)
      expect(target_path).to start_with(File.join(Dir.current, ".deleted_files"))
      expect(target_path).to contain(File.join(temp_dir, "sub"))
      expect(File.exists?(target_path)).to be_true
      expect(File.read(target_path)).to eq("doomed content")
      expect(File.basename(target_path)).to match(/\A\d{8}_\d{6}_\d{3}_victim\.txt\z/)
    end
  end

  context "deletes a file located in the root directory" do
    let(:root_file) { "delete_me_root_test.txt" }

    before { File.write(root_file, "root content") }

    after { File.delete?(root_file) }

    it "moves the file directly into the .deleted_files folder" do
      result = parse_run_result(runner.execute(make_args(file_path: root_file)))

      expect(result[:success]).to be_true

      message = result[:data].as_h["message"].as_s
      expect(message).to contain("File deleted successfully")

      expect(File.exists?(root_file)).to be_false

      target_path = extract_target_path(message).as(String)
      expect(File.dirname(target_path)).to eq(File.join(Dir.current, ".deleted_files"))
      expect(File.exists?(target_path)).to be_true
      expect(File.basename(target_path)).to match(/\A\d{8}_\d{6}_\d{3}_delete_me_root_test\.txt\z/)
    end
  end

  # -------------------------------------------------
  # Protection scenarios
  # -------------------------------------------------

  context "refuses to delete a file from the .deleted_files folder" do
    let(:deleted_file) { File.join(".deleted_files", "old_file.txt") }

    before do
      Dir.mkdir_p(".deleted_files")
      File.write(deleted_file, "to be recovered")
    end

    it "returns an error and leaves the file in place" do
      result = parse_run_result(runner.execute(make_args(file_path: deleted_file)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/Cannot delete files from the/)
      expect(File.read(deleted_file)).to eq("to be recovered")
    end
  end

  # -------------------------------------------------
  # Validation and error scenarios
  # -------------------------------------------------

  context "fails when file_path is not provided" do
    it "returns an error" do
      result = parse_run_result(runner.execute(make_args))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/The required file_path was not specified/)
    end
  end

  context "fails when the file does not exist" do
    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: File.join(temp_dir, "ghost.txt"))))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/does not exist or is not a file/)
    end
  end

  context "fails when the path is a directory" do
    let(:sub_dir) { File.join(temp_dir, "a_dir") }

    before { Dir.mkdir_p(sub_dir) }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: sub_dir)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/does not exist or is not a file/)
    end
  end

  context "fails when the path resolves outside the current directory" do
    let(:outside_path) { File.tempname("_outside.txt") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: outside_path)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/is not allowed/)
    end
  end
end
