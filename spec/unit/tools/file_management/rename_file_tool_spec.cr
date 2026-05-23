require "../../../spec_helper"
require "json"

Spectator.describe Tools::FileManagement::RenameFileTool do
  let(:temp_dir) { File.expand_path("spec/tmp_rename_test") }
  let(:runner) { Tools::FileManagement::RenameFileTool::Runner.new }

  def rm_rf(path)
    return unless path.starts_with?(temp_dir)
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

  def parse_run_result(result_json)
    parsed = JSON.parse(result_json)
    hash_val = parsed.as_h?
    if hash_val
      err = hash_val["error"]?
      if err
        return {success: false, data: parsed, error_msg: err.as_s}
      end
    end
    {success: true, data: parsed, error_msg: nil}
  end

  # -------------------------------------------------
  # Successful rename scenarios
  # -------------------------------------------------

  context "renames a file in the same directory" do
    let(:file_path) { File.join(temp_dir, "old_name.txt") }
    let(:new_path) { File.join(temp_dir, "new_name.txt") }

    before do
      File.write(file_path, "content")
    end

    it "returns success with the old and new names" do
      Dir.cd(temp_dir) do
        args = {
          "source_path" => "old_name.txt",
          "target_path" => "new_name.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:error_msg]).to be_nil
        expect(result[:data]["message"].as_s).to match(/old_name\.txt/)
        expect(result[:data]["message"].as_s).to match(/new_name\.txt/)
        expect(File.exists?(file_path)).to be_false
        expect(File.exists?(new_path)).to be_true
        expect(File.read(new_path)).to eq("content")
      end
    end
  end

  context "moves a file to a subdirectory" do
    let(:file_path) { File.join(temp_dir, "file.txt") }
    let(:target_dir) { File.join(temp_dir, "subdir") }
    let(:new_path) { File.join(target_dir, "file.txt") }

    before do
      File.write(file_path, "move content")
      Dir.mkdir_p(target_dir)
    end

    it "moves the file and returns success" do
      Dir.cd(temp_dir) do
        args = {
          "source_path" => "file.txt",
          "target_path" => "subdir/file.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:error_msg]).to be_nil
        expect(File.exists?(file_path)).to be_false
        expect(File.exists?(new_path)).to be_true
      end
    end
  end

  context "renames a file with spaces in the filename" do
    let(:file_path) { File.join(temp_dir, "old file name.txt") }
    let(:new_path) { File.join(temp_dir, "new file name.txt") }

    before do
      File.write(file_path, "spaces content")
    end

    it "renames the file successfully" do
      Dir.cd(temp_dir) do
        args = {
          "source_path" => "old file name.txt",
          "target_path" => "new file name.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(File.exists?(new_path)).to be_true
      end
    end
  end

  context "renames a file with special characters" do
    let(:file_path) { File.join(temp_dir, "test-file_2024.txt") }
    let(:new_path) { File.join(temp_dir, "new-test_v1.txt") }

    before do
      File.write(file_path, "special content")
    end

    it "renames the file with special chars successfully" do
      Dir.cd(temp_dir) do
        args = {
          "source_path" => "test-file_2024.txt",
          "target_path" => "new-test_v1.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(File.exists?(new_path)).to be_true
      end
    end
  end

  # -------------------------------------------------
  # Security scenarios
  # -------------------------------------------------

  context "blocks renaming paths resolved outside the current directory" do
    it "returns an error when source_path escapes current dir" do
      args = {
        "source_path" => "../outside_dir/file.txt",
        "target_path" => "some_name.txt",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/not allowed/)
    end
  end

  context "blocks renaming a file inside the .deleted_files directory" do
    let(:deleted_dir) { File.expand_path(".deleted_files") }
    let(:file_in_deleted) { File.join(deleted_dir, "temp_file.txt") }

    before do
      Dir.mkdir_p(deleted_dir) unless Dir.exists?(deleted_dir)
      File.write(file_in_deleted, "deleted content")
    end

    after do
      File.delete?(file_in_deleted)
      if Dir.exists?(deleted_dir) && Dir.empty?(deleted_dir)
        Dir.delete(deleted_dir)
      end
    end

    it "returns an error when trying to rename a file in .deleted_files" do
      Dir.cd(temp_dir) do
        args = {
          "source_path" => ".deleted_files/temp_file.txt",
          "target_path" => "renamed.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_false
        expect(result[:error_msg]).not_to be_nil
        expect(result[:error_msg]).to match(/deleted_files/)
      end
    end
  end

  # -------------------------------------------------
  # Missing parameter scenarios
  # -------------------------------------------------

  context "fails when source_path is not provided" do
    it "returns an error" do
      args = {
        "target_path" => "some_name.txt",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/source_path/)
    end
  end

  context "fails when target_path is not provided" do
    it "returns an error" do
      args = {
        "source_path" => "some_name.txt",
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/target_path/)
    end
  end

  # -------------------------------------------------
  # Non-existent file scenario
  # -------------------------------------------------

  context "fails when the source file does not exist" do
    it "returns an error for a non-existent source path" do
      Dir.cd(temp_dir) do
        args = {
          "source_path" => "nonexistent_file.txt",
          "target_path" => "new_file.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_false
        expect(result[:error_msg]).not_to be_nil
        expect(result[:error_msg]).to match(/does not exist/)
      end
    end
  end

  # -------------------------------------------------
  # Target already exists scenario
  # -------------------------------------------------

  context "fails when the target name already exists" do
    let(:source_file) { File.join(temp_dir, "source.txt") }
    let(:target_file) { File.join(temp_dir, "target.txt") }

    before do
      File.write(source_file, "source content")
      File.write(target_file, "target content")
    end

    it "returns an error when target path already exists" do
      Dir.cd(temp_dir) do
        args = {
          "source_path" => "source.txt",
          "target_path" => "target.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_false
        expect(result[:error_msg]).not_to be_nil
        expect(result[:error_msg]).to match(/already exists/)
      end
    end
  end
end
