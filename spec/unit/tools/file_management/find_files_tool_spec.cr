require "../../../spec_helper"
require "json"

Spectator.describe Tools::FileManagement::FindFilesTool do
  let(:temp_dir) { "spec/tmp_find_test" }
  let(:runner) { Tools::FileManagement::FindFilesTool::Runner.new }

  def rm_rf(path)
    return unless path.starts_with?("spec/tmp_find")
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
  # Successful glob matching scenarios
  # -------------------------------------------------

  context "finds files matching a simple glob pattern" do
    let(:file_a) { File.join(temp_dir, "file_a.txt") }
    let(:file_b) { File.join(temp_dir, "file_b.txt") }
    let(:file_c) { File.join(temp_dir, "file_c.log") }

    before do
      File.write(file_a, "a")
      File.write(file_b, "b")
      File.write(file_c, "c")
    end

    it "returns matching file paths as a JSON array" do
      args = {
        "expression" => "*.txt",
        "path"       => temp_dir,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:error_msg]).to be_nil
      expect(result[:data].as_a.size).to eq(2)
    end
  end

  context "finds both files and directories in nested paths" do
    let(:file_in_dir) { File.join(temp_dir, "subdir", "file.txt") }

    before do
      Dir.mkdir_p(File.dirname(file_in_dir))
      File.write(file_in_dir, "hello")
    end

    it "returns matching files when using recursive glob" do
      args = {
        "expression" => "**/*",
        "path"       => temp_dir,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a
      expect(matches.size.to_i).to be_gt(0)
      match_strings = matches.map(&.as_s)
      expect(match_strings).to contain(file_in_dir)
    end
  end

  # -------------------------------------------------
  # Sorting scenarios
  # -------------------------------------------------

  context "applies sorting by default" do
    let(:file_c) { File.join(temp_dir, "c.txt") }
    let(:file_a) { File.join(temp_dir, "a.txt") }
    let(:file_b) { File.join(temp_dir, "b.txt") }

    before do
      File.write(file_c, "c")
      File.write(file_a, "a")
      File.write(file_b, "b")
    end

    it "returns files in sorted order by default" do
      args = {
        "expression" => "*.txt",
        "path"       => temp_dir,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a.map(&.as_s)
      expect(matches).to eq(matches.sort)
    end
  end

  context "does not sort when sort is false" do
    let(:file_c) { File.join(temp_dir, "c.txt") }
    let(:file_a) { File.join(temp_dir, "a.txt") }

    before do
      File.write(file_c, "c")
      File.write(file_a, "a")
    end

    it "returns files in whatever order the glob provides" do
      args = {
        "expression" => "*.txt",
        "path"       => temp_dir,
        "sort"       => false,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(2)
    end
  end

  # -------------------------------------------------
  # Max limit scenarios
  # -------------------------------------------------

  context "respects the max parameter" do
    let(:files) do
      (1..10).map { |i| File.join(temp_dir, "file_#{i}.txt") }
    end

    before do
      files.each { |f| File.write(f, "content") }
    end

    it "limits results to the specified max count" do
      args = {
        "expression" => "*.txt",
        "path"       => temp_dir,
        "max"        => 3,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(3)
    end

    it "returns all matches when max exceeds the number of matches" do
      args = {
        "expression" => "*.txt",
        "path"       => temp_dir,
        "max"        => 999,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(10)
    end
  end

  # -------------------------------------------------
  # Default path scenarios
  # -------------------------------------------------

  context "requires path in all requests" do
    before do
      File.write(File.join(temp_dir, "found.txt"), "yes")
    end

    it "fails when path is not provided" do
      Dir.cd(temp_dir) do
        args = {
          "expression" => "*.txt",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_false
      end
    end

    it "fails on empty string path" do
      Dir.cd(temp_dir) do
        args = {
          "expression" => "*.txt",
          "path"       => "",
        }

        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_false
      end
    end
  end

  # -------------------------------------------------
  # Security scenarios
  # -------------------------------------------------

  context "blocks paths resolved outside the current directory" do
    let(:outside_path) { File.tempname("_outside.txt") }

    it "returns an error when the glob resolves outside" do
      args = {
        "expression" => "*",
        "path"       => outside_path,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/outside current directory/)
    end
  end

  context "blocks paths containing '..' navigation" do
    let(:safe_dir) { File.join(temp_dir, "safe") }

    before { Dir.mkdir_p(safe_dir) }

    it "returns an error when pattern contains ../" do
      args = {
        "expression" => "../../../etc/*.txt",
        "path"       => safe_dir,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/Reverse path navigation/)
    end

    it "returns an error when pattern contains /.." do
      args = {
        "expression" => "../..",
        "path"       => safe_dir,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/Reverse path navigation/)
    end
  end

  # -------------------------------------------------
  # Error handling scenarios
  # -------------------------------------------------

  context "fails when expression is not provided" do
    it "returns an error" do
      args = {} of String => JSON::Any

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/required glob `expression` was not specified/)
    end
  end

  context "handles invalid glob patterns gracefully" do
    it "returns an error when the glob contains invalid syntax" do
      args = {
        "expression" => "[invalid",
        "path"       => temp_dir,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a
      expect(matches.size.to_i).to eq(0)
    end
  end

  context "returns empty results when no files match" do
    it "succeeds with an empty JSON array" do
      args = {
        "expression" => "*.xyz_nonexistent",
        "path"       => temp_dir,
      }

      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(0)
    end
  end
end
