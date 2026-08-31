require "../../../spec_helper"
require "json"

Spectator.describe Tools::TextEditing::ReplaceTextInTextFileTool do
  # -----------------------------------------------------------------
  # Shared test fixtures
  # -----------------------------------------------------------------
  let(:temp_dir) { "spec/tmp_test" }
  let(:file_path) { File.join(temp_dir, "sample.txt") }

  before { Dir.mkdir_p(temp_dir) }
  after do
    File.delete?(file_path)
    Dir.delete?(temp_dir)
  end

  let(:runner) { Tools::TextEditing::ReplaceTextInTextFileTool::Runner.new }

  # -----------------------------------------------------------------
  # Successful replacement scenarios
  # -----------------------------------------------------------------
  context "replaces the first occurrence by default" do
    let(:content) { "first line old text\nsecond line old text\nthird line" }
    before { File.write(file_path, content) }

    it "returns one replacement and a single hunk" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
      expect(result["changes"].as_a.size).to be 1
    end

    it "writes the correct content to the file" do
      runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
      }.to_json))

      expect(File.read(file_path)).to eq "first line new text\nsecond line old text\nthird line"
    end

    it "includes the correct before and after in the hunk" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["before"].as_s).to contain "old"
      expect(hunk["after"].as_s).to contain "new"
      expect(hunk["after"].as_s).not_to contain "first line old text"
    end

    it "returns the file_path in the response" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["file_path"].as_s).to eq file_path
    end
  end

  context "replaces a specific occurrence by number" do
    let(:content) { "alpha old one\nbeta\ngamma old two\ndelta\nepsilon old three" }
    before { File.write(file_path, content) }

    it "replaces only the second occurrence when occurrence is 2" do
      result_json = runner.execute(JSON.parse({
        "file_path"  => file_path,
        "old_str"    => "old",
        "new_str"    => "new",
        "occurrence" => 2,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
      expect(File.read(file_path)).to eq "alpha old one\nbeta\ngamma new two\ndelta\nepsilon old three"
    end

    it "leaves the first and third occurrences intact" do
      runner.execute(JSON.parse({
        "file_path"  => file_path,
        "old_str"    => "old",
        "new_str"    => "new",
        "occurrence" => 2,
      }.to_json))

      content = File.read(file_path)
      expect(content).to contain "alpha old one"
      expect(content).to contain "gamma new two"
      expect(content).to contain "epsilon old three"
    end

    it "reports the correct line in the hunk for the targeted occurrence" do
      result_json = runner.execute(JSON.parse({
        "file_path"  => file_path,
        "old_str"    => "old",
        "new_str"    => "new",
        "occurrence" => 3,
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      # "old three" is on line 5; with context clamped to file end (5 lines total)
      expect(hunk["end_line"].as_i).to be 5
    end
  end

  context "fails when occurrence exceeds the number of matches" do
    let(:content) { "one old here\ntwo old here\nthree" }
    before { File.write(file_path, content) }

    it "returns an error mentioning the expected and actual count" do
      result_json = runner.execute(JSON.parse({
        "file_path"  => file_path,
        "old_str"    => "old",
        "new_str"    => "new",
        "occurrence" => 5,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "Expected occurrence 5"
      expect(result["error"].as_s).to contain "only 2 matches"
    end

    it "does not modify the file" do
      runner.execute(JSON.parse({
        "file_path"  => file_path,
        "old_str"    => "old",
        "new_str"    => "new",
        "occurrence" => 5,
      }.to_json))

      expect(File.read(file_path)).to eq content
    end
  end

  context "replaces all occurrences when `occurrence` is -1" do
    let(:content) { "one old here\ntwo old here\nthree old here\nfour" }
    before { File.write(file_path, content) }

    it "returns the correct replacement count" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 3
    end

    it "writes all replacements to the file" do
      runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
        "occurrence" => -1,
      }.to_json))

      expect(File.read(file_path)).to eq "one new here\ntwo new here\nthree new here\nfour"
    end

    it "merges close hunks into a single change entry" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h

      # All three matches are within 2 lines of each other, so context overlaps
      expect(result["changes"].as_a.size).to be 1
    end

    it "the merged hunk before contains all original matches" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["before"].as_s).to contain "one old here"
      expect(hunk["before"].as_s).to contain "two old here"
      expect(hunk["before"].as_s).to contain "three old here"
    end

    it "the merged hunk after has all replacements applied" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["after"].as_s).to contain "one new here"
      expect(hunk["after"].as_s).to contain "two new here"
      expect(hunk["after"].as_s).to contain "three new here"
      expect(hunk["after"].as_s).not_to contain "old"
    end
  end

  context "produces separate hunks for far-apart matches" do
    let(:content) do
      String.build do |io|
        20.times { io << "filler line\n" }
        io << "target one\n"
        10.times { io << "middle line\n" }
        io << "target two\n"
        10.times { io << "trailing line\n" }
      end
    end
    before { File.write(file_path, content) }

    it "returns separate change entries for each distant match" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "target",
        "new_str"   => "replaced",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 2
      expect(result["changes"].as_a.size).to be 2
    end

    it "reports correct line ranges for each hunk" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "target",
        "new_str"   => "replaced",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h
      changes = result["changes"].as_a.map &.as_h

      # Matches are on lines 21 and 32; with 2 lines of context each
      # they should be well separated
      expect(changes[0]["end_line"].as_i < changes[1]["start_line"].as_i).to be_true
    end

    it "each hunk only shows its own region" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "target",
        "new_str"   => "replaced",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h
      changes = result["changes"].as_a.map &.as_h

      expect(changes[0]["before"].as_s).to contain "target one"
      expect(changes[0]["before"].as_s).not_to contain "target two"
      expect(changes[1]["before"].as_s).to contain "target two"
      expect(changes[1]["before"].as_s).not_to contain "target one"
    end
  end

  context "merges adjacent hunks when context lines overlap" do
    let(:content) { "top\nmatch_a\nmiddle\nmatch_b\nbottom" }
    before { File.write(file_path, content) }

    it "combines matches separated by only one line into a single hunk" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "match_",
        "new_str"   => "replaced_",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h

      # match_a on line 2 (context: lines 1-4), match_b on line 4 (context: lines 2-5)
      # These overlap, so they merge into one hunk
      expect(result["changes"].as_a.size).to be 1
    end
  end

  context "clamps context to file boundaries" do
    let(:content) { "alpha\nbeta\ngamma" }
    before { File.write(file_path, content) }

    it "handles a match on the first line without going below line 1" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "alpha",
        "new_str"   => "ALPHA",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["start_line"].as_i).to be 1
    end

    it "handles a match on the last line without exceeding total lines" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "gamma",
        "new_str"   => "GAMMA",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["end_line"].as_i).to be 3
    end

    it "the hunk for the first line includes all available context below" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "alpha",
        "new_str"   => "ALPHA",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      # Line 1 match, context extends to line 3 (2 + CONTEXT_LINES, clamped to 3)
      expect(hunk["end_line"].as_i).to be 3
    end
  end

  context "handles multi-line replacements" do
    let(:content) { "line one\nold_a\nold_b\nold_c\nline five\n" }
    before { File.write(file_path, content) }

    it "replaces a multi-line block correctly" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old_a\nold_b\nold_c",
        "new_str"   => "new_block",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
    end

    it "writes the correct file content" do
      runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old_a\nold_b\nold_c",
        "new_str"   => "new_block",
      }.to_json))

      expect(File.read(file_path)).to eq "line one\nnew_block\nline five\n"
    end

    it "spans the correct line range in the hunk" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old_a\nold_b\nold_c",
        "new_str"   => "new_block",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      # The match spans lines 2-4, with context it should cover at least that
      expect(hunk["start_line"].as_i <= 2).to be_true
      expect(hunk["end_line"].as_i >= 4).to be_true
    end
  end

  context "handles replacement that expands line count" do
    let(:content) { "start\nsingle line\nend" }
    before { File.write(file_path, content) }

    it "replaces one line with multiple lines" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "single line",
        "new_str"   => "first replacement\nsecond replacement\nthird replacement",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
      expect(File.read(file_path)).to eq "start\nfirst replacement\nsecond replacement\nthird replacement\nend"
    end

    it "the before hunk shows the original single line" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "single line",
        "new_str"   => "first replacement\nsecond replacement\nthird replacement",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["before"].as_s).to contain "single line"
    end

    it "the after hunk shows the expanded lines" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "single line",
        "new_str"   => "first replacement\nsecond replacement\nthird replacement",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["after"].as_s).to contain "first replacement"
      expect(hunk["after"].as_s).to contain "second replacement"
      expect(hunk["after"].as_s).to contain "third replacement"
    end
  end

  context "handles a single-line file" do
    let(:content) { "just one line with old text" }
    before { File.write(file_path, content) }

    it "replaces correctly" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
      expect(File.read(file_path)).to eq "just one line with new text"
    end

    it "the hunk covers only line 1" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "old",
        "new_str"   => "new",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["start_line"].as_i).to be 1
      expect(hunk["end_line"].as_i).to be 1
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
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "does not exist"
    end
  end

  context "fails when the old string is not found" do
    let(:content) { "no old here" }
    before { File.write(file_path, content) }

    it "returns an error mentioning the missing string" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "missing",
        "new_str"   => "something",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "Unable to find old string"
    end

    it "does not modify the file" do
      runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "missing",
        "new_str"   => "something",
      }.to_json))

      expect(File.read(file_path)).to eq content
    end
  end

  context "fails when required parameters are missing" do
    let(:content) { "some content" }
    before { File.write(file_path, content) }

    it "returns an error when file_path is missing" do
      result_json = runner.execute(JSON.parse({
        "old_str" => "some",
        "new_str" => "other",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"].as_s).to contain "`file_path`"
    end

    it "returns an error when old_str is missing" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "new_str"   => "other",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"].as_s).to contain "`old_str`"
    end

    it "returns an error when new_str is missing" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "some",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["error"].as_s).to contain "`new_str`"
    end
  end

  context "rejects paths outside the current directory" do
    let(:file_path) { File.tempname("_outside.txt") }

    it "returns an error" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "test",
        "new_str"   => "changed",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "not allowed"
    end
  end

  # -----------------------------------------------------------------
  # Edge cases
  # -----------------------------------------------------------------
  context "handles replacing with an empty string (deletion)" do
    let(:content) { "keep this\nremove me\nkeep this too" }
    before { File.write(file_path, content) }

    it "deletes the matched text" do
      runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "\nremove me",
        "new_str"   => "",
      }.to_json))

      expect(File.read(file_path)).to eq "keep this\nkeep this too"
    end

    it "reports the hunk for the deletion" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "\nremove me",
        "new_str"   => "",
      }.to_json))
      result = JSON.parse(result_json).as_h
      hunk = result["changes"].as_a.first.as_h

      expect(hunk["before"].as_s).to contain "remove me"
      expect(hunk["after"].as_s).not_to contain "remove me"
    end
  end

  context "handles Unicode content" do
    let(:content) { "greet with → arrow\nsecond line\n" }
    before { File.write(file_path, content) }

    it "replaces Unicode text correctly" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "→",
        "new_str"   => "⇒",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
      expect(File.read(file_path)).to eq "greet with ⇒ arrow\nsecond line\n"
    end
  end

  context "handles whitespace-sensitive matching" do
    let(:content) { "  indented line\n\ttab line\nno indent" }
    before { File.write(file_path, content) }

    it "matches with exact indentation (spaces)" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "  indented line",
        "new_str"   => "  changed line",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
      expect(File.read(file_path)).to eq "  changed line\n\ttab line\nno indent"
    end

    it "does not match when tabs are used instead of spaces" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "\tindented line",
        "new_str"   => "changed line",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result).to have_key "error"
      expect(result["error"].as_s).to contain "Unable to find old string"
    end
  end

  context "does not match partial words" do
    let(:content) { "cat category catalog" }
    before { File.write(file_path, content) }

    it "still matches substrings (exact byte matching, not word boundaries)" do
      # The tool does byte-for-byte matching, so "cat" matches in all three words
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "cat",
        "new_str"   => "dog",
        "occurrence" => -1,
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 3
    end
  end

  context "handles a file with no trailing newline" do
    let(:content) { "first\nsecond\nlast line no newline" }
    before { File.write(file_path, content) }

    it "replaces on the last line correctly" do
      result_json = runner.execute(JSON.parse({
        "file_path" => file_path,
        "old_str"   => "no newline",
        "new_str"   => "has newline",
      }.to_json))
      result = JSON.parse(result_json).as_h

      expect(result["replacements"].as_i).to be 1
      expect(File.read(file_path)).to eq "first\nsecond\nlast line has newline"
    end
  end
end
