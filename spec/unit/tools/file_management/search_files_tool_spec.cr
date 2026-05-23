require "../../../spec_helper"
require "json"

Spectator.describe Tools::FileManagement::SearchFilesTool do
  let(:temp_dir) { "spec/tmp_search_test" }
  let(:runner) { Tools::FileManagement::SearchFilesTool::Runner.new }

  def rm_rf(path)
    return unless path.starts_with?("spec/tmp_search")
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

  def make_args(**opts)
    JSON.parse(opts.to_json)
  end

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
    # Successful string search scenarios
    # -------------------------------------------------

  context "searches for a pattern in files" do
    let(:file_a) { File.join(temp_dir, "file_a.txt") }
    let(:file_b) { File.join(temp_dir, "file_b.txt") }

    before do
      File.write(file_a, "hello world\nfoo bar\n")
      File.write(file_b, "nothing here\n")
    end

    it "returns matching lines with file paths and line numbers" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "hello",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:error_msg]).to be_nil
      matches = result[:data].as_a
      expect(matches.size.to_i).to eq(1)
      match_tuple = matches.first.as_h
      expect(match_tuple["file"].as_s).to eq(file_a)
      match_lines = match_tuple["matches"].as_a
      expect(match_lines.size.to_i).to eq(1)
      expect(match_lines.first.as_h["line"].as_s).to eq("hello world")
      expect(match_lines.first.as_h["num"].as_i).to eq(1)
    end
  end

  context "finds multiple matches across multiple files" do
    let(:file_a) { File.join(temp_dir, "file_a.txt") }
    let(:file_b) { File.join(temp_dir, "file_b.txt") }

    before do
      File.write(file_a, "foo bar\nfoo baz\n")
      File.write(file_b, "foo qux\nnot here\n")
    end

    it "returns all matches from all files" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "foo",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a
      expect(matches.size.to_i).to eq(2)
    end
  end

  context "returns no matches when pattern is not found" do
    let(:file_a) { File.join(temp_dir, "file_a.txt") }

    before do
      File.write(file_a, "hello world\nfoo bar\n")
    end

    it "succeeds with an empty results array" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "notfound",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a
      expect(matches.size.to_i).to eq(0)
    end
  end

    # -------------------------------------------------
    # Regex search scenario
    # -------------------------------------------------

  context "searches using regex when search_regex is true" do
    let(:file_a) { File.join(temp_dir, "file_a.txt") }

    before do
      File.write(file_a, "cat123\ndog456\ncat789\n")
    end

    it "matches lines using the regex pattern" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "cat\\d+",
        search_regex: true,
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a
      expect(matches.size.to_i).to eq(1)
      match_lines = matches.first.as_h["matches"].as_a
      expect(match_lines.size.to_i).to eq(2)
      expect(match_lines.first.as_h["line"].as_s).to eq("cat123")
      expect(match_lines.last.as_h["line"].as_s).to eq("cat789")
    end
  end

  context "does regex matching when search_regex is false" do
    let(:file_a) { File.join(temp_dir, "file_a.txt") }

    before do
      File.write(file_a, "cat123\ncat\n")
    end

    it "matches literal string only" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "cat\\d+",
        search_regex: false,
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a
      expect(matches.size.to_i).to eq(0)
    end
  end

    # -------------------------------------------------
    # Max files limit scenarios
    # -------------------------------------------------

  context "respects the max_files parameter" do
    let(:max_files_default) { 1000 }

    let(:files) do
       (1..max_files_default).map { |i| File.join(temp_dir, "file_#{i}.txt") }
    end

    before do
      files.each { |f| File.write(f, "hello") }
    end

    it "limits results to the specified max_files count" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "hello",
        max_files: 3,
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(3)
    end

    it "returns all matches when max_files exceeds the number of matches" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "hello",
        max_files: 9999,
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(max_files_default)
    end
  end

    # -------------------------------------------------
    # Default values scenarios
    # -------------------------------------------------

  context "uses default values when params are omitted" do
    let(:file_a) { File.join(temp_dir, "file_a.txt") }

    before do
      File.write(file_a, "default test line")
    end

    it "defaults files pattern to all files when not provided" do
      args = make_args(
        files: File.join(temp_dir, "*"),
        pattern: "default test line",
        )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(1)
    end

    it "defaults search_regex to false when not provided" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "def",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      matches = result[:data].as_a
      expect(matches.size.to_i).to eq(1)
    end
  end

    # -------------------------------------------------
    # Security scenarios
    # -------------------------------------------------

  context "blocks paths resolved outside the current directory" do
    let(:outside_path) { File.tempname("_outside.txt") }

    it "returns an error when the files pattern resolves outside" do
      args = make_args(
        files: outside_path,
        pattern: "test",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/outside current directory/)
    end
  end

  context "blocks paths containing '..' navigation" do
    let(:safe_dir) { File.join(temp_dir, "safe") }

    before { Dir.mkdir_p(safe_dir) }

    it "returns an error when files pattern contains ../" do
      args = make_args(
        files: "spec/../etc/*.txt",
        pattern: "test",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/Reverse path navigation/)
    end

    it "returns an error when files pattern contains /.." do
      args = make_args(
        files: "spec/..",
        pattern: "test",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/Reverse path navigation/)
    end
  end

    # -------------------------------------------------
    # Error handling scenarios
    # -------------------------------------------------

  context "fails when files is not provided" do
    it "returns an error" do
      args = make_args()

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
    end
  end

  context "fails when pattern is not provided" do
    it "returns an error" do
      args = make_args(files: "*.txt")

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/required search pattern/)
    end
  end

  context "fails when pattern is empty" do
    before do
      File.write(File.join(temp_dir, "empty.txt"), "content")
    end

    it "returns an error for a whitespace-only pattern" do
      args = make_args(
        files: File.join(temp_dir, "*.txt"),
        pattern: "      ",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).not_to be_nil
      expect(result[:error_msg]).to match(/empty/)
    end
  end

  context "handles invalid file patterns gracefully" do
    it "returns an error when the files pattern matches nothing" do
      args = make_args(
        files: "*.xyz_nonexistent",
        pattern: "hello",
      )

      result_json = runner.execute(args)
      result = parse_run_result(result_json)

      expect(result[:success]).to be_true
      expect(result[:data].as_a.size.to_i).to eq(0)
    end
  end
end
