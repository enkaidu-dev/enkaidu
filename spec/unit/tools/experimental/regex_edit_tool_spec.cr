require "../../../spec_helper"
require "json"

Spectator.describe Tools::Experimental::RegexTextEditTool do
  # -------------------------------------------------
  # Shared test fixtures
  # -------------------------------------------------
  let(:temp_dir) { File.expand_path("spec/tmp_regex_test") }
  let(:file_path) { "sample.txt" }
  let(:abs_file_path) { File.join(temp_dir, "sample.txt") }
  let(:runner) { Tools::Experimental::RegexTextEditTool::Runner.new }

  # Recursively delete a directory for cleanup
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

  # -------------------------------------------------
  # Helper methods
  # -------------------------------------------------
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
  # Successful replacement scenarios
  # -------------------------------------------------
  context "replaces a single match" do
    let(:content) { "hello world" }
    before { File.write(abs_file_path, content) }

    it "succeeds and returns correct replacement count and new content" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "world",
        "new_str"   => "universe",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:error_msg]).to be_nil
        expect(result[:data]["replacements"].as_i).to be 1
        expect(result[:data]["new_content"].as_s).to eq("hello universe")
        expect(result[:data]["file_path"].as_s).to eq("sample.txt")
      end
    end
  end

  context "replaces multiple matches across the file" do
    let(:content) { "foo bar foo baz foo" }
    before { File.write(abs_file_path, content) }

    it "replaces all occurrences and reports correct count" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "foo",
        "new_str"   => "qux",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 3
        expect(result[:data]["new_content"].as_s).to eq("qux bar qux baz qux")
      end
    end
  end

  context "replaces across multiple lines with multiline regex" do
    let(:content) { "line one\ntwo\nline three\nfour\n" }
    before { File.write(abs_file_path, content) }

    it "matches word boundaries with /m flag" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "(?m)^line ",
        "new_str"   => ">>> ",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 2
        expect(result[:data]["new_content"].as_s).to eq(">>> one\ntwo\n>>> three\nfour\n")
      end
    end
  end

  context "handles captured groups in patterns" do
    let(:content) { "hello world hello" }
    before { File.write(abs_file_path, content) }

    it "matches the full pattern with capture groups" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "(hello) (world)",
        "new_str"   => "WORLD HELLO",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 1
        expect(result[:data]["new_content"].as_s).to eq("WORLD HELLO hello")
      end
    end
  end

  context "replaces regex metacharacters in pattern" do
    let(:content) { "price: $10, price: $20, price: $30" }
    before { File.write(abs_file_path, content) }

    it "handles dollar sign escaped in literal replacement context" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "\\$\\d+",
        "new_str"   => "N/A",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 3
        expect(result[:data]["new_content"].as_s).to eq("price: N/A, price: N/A, price: N/A")
      end
    end
  end

  context "replaces to an empty string" do
    let(:content) { "abc 123 def 456 ghi" }
    before { File.write(abs_file_path, content) }

    it "removes all matching digit sequences" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "\\d+",
        "new_str"   => "",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 2
        expect(result[:data]["new_content"].as_s).to eq("abc  def  ghi")
      end
    end
  end

  context "handles unicode content in the file" do
    let(:content) { "cafe\u0301 cafe\u0301 cafe\u0301\n" }
    before { File.write(abs_file_path, content) }

    it "matches unicode characters correctly" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "cafe\u0301",
        "new_str"   => "cafe",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 3
        expect(result[:data]["new_content"].as_s).to eq("cafe cafe cafe\n")
      end
    end
  end

  context "handles unicode patterns matched by word chars" do
    let(:content) { "a1 b2 c3\n" }
    before { File.write(abs_file_path, content) }

    it "matches word characters across newlines" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "(?m)(\\w)(\\d)",
        "new_str"   => "X",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 3
        expect(result[:data]["new_content"].as_s).to eq("X X X\n")
      end
    end
  end

  context "handles a single-line file" do
    let(:content) { "single line with MATCH to replace" }
    before { File.write(abs_file_path, content) }

    it "replaces the match on the single line" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "MATCH",
        "new_str"   => "RESULT",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 1
        expect(result[:data]["new_content"].as_s).to eq("single line with RESULT to replace")
      end
    end
  end

  context "replaces with lookbehind assertion" do
    let(:content) { "123 USD 456 USD 789 EUR" }
    before { File.write(abs_file_path, content) }

    it "matches only USD preceded by a space" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "(?<=\\s)USD(?=\\s|$)",
        "new_str"   => "EUR",
      }
      Dir.cd(temp_dir) do
        result_json = runner.execute(JSON.parse(args.to_json))
        result = parse_run_result(result_json)

        expect(result[:success]).to be_true
        expect(result[:data]["replacements"].as_i).to be 2
        expect(result[:data]["new_content"].as_s).to eq("123 EUR 456 EUR 789 EUR")
      end
    end
  end

  # -------------------------------------------------
  # Missing parameter errors
  # -------------------------------------------------
  context "fails when file_path is not specified" do
    it "returns an error mentioning file_path" do
      args = {
        "pattern" => "foo",
        "new_str" => "bar",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("file_path")
    end
  end

  context "fails when pattern is not specified" do
    before { File.write(abs_file_path, "hello") }

    it "returns an error mentioning pattern" do
      args = {
        "file_path" => "sample.txt",
        "new_str"   => "world",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("pattern")
    end
  end

  context "fails when new_str is not specified" do
    before { File.write(abs_file_path, "hello") }

    it "returns an error mentioning new_str" do
      args = {
        "file_path" => "sample.txt",
        "pattern"   => "hello",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("new_str")
    end
  end

  # -------------------------------------------------
  # File-related errors
  # -------------------------------------------------
  context "fails when the specified file does not exist" do
    it "returns an error mentioning the file does not exist" do
      args = {
        "file_path" => "nonexistent.txt",
        "pattern"   => "foo",
        "new_str"   => "bar",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("does not exist")
    end
  end

  context "fails when the regex matches nothing in the file" do
    let(:content) { "nothing matches this pattern" }
    before { File.write(abs_file_path, content) }

    it "returns an error about no strings being found" do
      args = {
        "file_path" => abs_file_path,
        "pattern"   => "xyzxyzxyz",
        "new_str"   => "replacement",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("Unable to find")
    end
  end

  context "fails when regex is invalid" do
    let(:content) { "some text" }
    before { File.write(abs_file_path, content) }

    it "returns an error for malformed regex" do
      args = {
        "file_path" => abs_file_path,
        "pattern"   => "[invalid",
        "new_str"   => "replaced",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("Invalid")
    end
  end

  # -------------------------------------------------
  # Security scenarios
  # -------------------------------------------------
  context "blocks paths resolved outside the current directory" do
    let(:outside_path) { File.tempname("_outside.txt") }

    after { File.delete?(outside_path) }

    it "returns an error indicating the path is not allowed" do
      File.write(outside_path, "some content")

      args = {
        "file_path" => outside_path,
        "pattern"   => "foo",
        "new_str"   => "bar",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("not allowed")
    end
  end

  context "blocks multiple ../ sequences in the path" do
    it "returns an error for deeply nested path traversal" do
      args = {
        "file_path" => "deep/../../../etc/passwd",
        "pattern"   => "foo",
        "new_str"   => "bar",
      }
      result_json = runner.execute(JSON.parse(args.to_json))
      result = parse_run_result(result_json)

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to contain("not allowed")
    end
  end
end
