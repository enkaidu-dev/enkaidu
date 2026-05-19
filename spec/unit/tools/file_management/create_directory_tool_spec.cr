require "../../../spec_helper"
require "json"

Spectator.describe Tools::FileManagement::CreateDirectoryTool do
  let(:temp_dir) { File.expand_path("spec/tmp_create_dir_test") }
  let(:runner) { Tools::FileManagement::CreateDirectoryTool::Runner.new }

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
         return { success: false, data: parsed, error_msg: err.as_s }
      end
    end
     { success: true, data: parsed, error_msg: nil }
  end

    # -------------------------------------------------
    # Successful directory creation scenarios
    # -------------------------------------------------

  context "creates a single-level directory" do
    let(:dir_path) { File.join(temp_dir, "new_directory") }

    it "returns success with the directory path" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "new_directory",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:error_msg]).to be_nil
        expect(result[:data]["directory_path"].as_s).to eq("new_directory")
        expect(result[:data]["status"].as_s).to eq("created")
        expect(File.exists?(dir_path)).to be_true
        expect(Dir.exists?(dir_path)).to be_true
      end
    end
  end

  context "creates a nested directory with intermediate paths missing" do
    let(:nested_dir) { File.join(temp_dir, "level1", "level2", "level3") }

    it "creates all intermediate directories and the final directory" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "level1/level2/level3",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:error_msg]).to be_nil
        expect(result[:data]["directory_path"].as_s).to eq("level1/level2/level3")
        expect(File.exists?(nested_dir)).to be_true
        expect(Dir.exists?(nested_dir)).to be_true
      end
    end
  end

  context "creates directory using forward slashes on any OS" do
    let(:dir_path) { File.join(temp_dir, "subdir", "another") }

    it "creates the full path successfully" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "subdir/another",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(File.exists?(dir_path)).to be_true
      end
    end
  end

    # -------------------------------------------------
    # Security scenarios
    # -------------------------------------------------

  context "blocks paths resolved outside the current directory" do
    it "returns an error when path contains ../ going outside temp_dir" do
      args = {
            "directory_path" => "../outside_dir",
          }

      # No Dir.cd - test runs from project root
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/outside/)
    end
  end

  context "blocks paths with multiple levels of parent navigation" do
    let(:safe_subdir) { File.join(temp_dir, "safe") }

    before { Dir.mkdir_p(safe_subdir) }

    it "returns an error when pattern contains../../" do
      args = {
            "directory_path" => "safe/../../etc/testdir",
          }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/outside/)
    end
  end

    # -------------------------------------------------
    # Missing parameter scenarios
    # -------------------------------------------------

  context "fails when directory_path is not provided" do
    it "returns an error" do
      args = {} of String => JSON::Any

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/directory_path/)
    end
  end

  context "fails when directory_path is nil" do
    it "returns an error" do
      args = {
            "directory_path" => nil,
          }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
    end
  end

    # -------------------------------------------------
    # Edge case scenarios
    # -------------------------------------------------

  context "handles empty string directory_path" do
    it "creates directory in current directory" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(File.exists?(temp_dir)).to be_true
      end
    end
  end

  context "handles existing directory gracefully" do
    let(:existing_dir) { File.join(temp_dir, "existing_dir") }

    before { Dir.mkdir_p(existing_dir) }

    it "succeeds even if directory already exists" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "existing_dir",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
      end
    end
  end

  context "handles partially existing nested directories" do
    let(:partial_dir) { File.join(temp_dir, "partial", "sub") }

    before { Dir.mkdir_p(File.dirname(partial_dir)) }

    it "creates the remaining subdirectory successfully" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "partial/sub",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(File.exists?(partial_dir)).to be_true
      end
    end
  end

  context "handles directory names with spaces" do
    let(:dir_path) { File.join(temp_dir, "my new directory") }

    it "creates the directory with spaces in the name" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "my new directory",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(File.exists?(dir_path)).to be_true
      end
    end
  end

  context "handles directory names with special characters" do
    let(:dir_path) { File.join(temp_dir, "test-dir_2024") }

    it "creates the directory with special characters" do
      Dir.cd(temp_dir) do
        args = {
              "directory_path" => "test-dir_2024",
            }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(File.exists?(dir_path)).to be_true
      end
    end
  end
end
