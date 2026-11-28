require "../../spec_helper"

Spectator.describe Tools::Compatibility do
  context "resolve" do
    it "maps deprecated names to their current names" do
      expect(Tools::Compatibility.resolve(["read_text_file", "find"])).to eq(["read_text", "find"])
    end

    it "leaves non-deprecated names unchanged" do
      expect(Tools::Compatibility.resolve(["find", "search", "date"])).to eq(["find", "search", "date"])
    end

    it "handles an empty enumerable" do
      expect(Tools::Compatibility.resolve([] of String)).to be_empty
    end

    it "maps every known deprecated name" do
      names = Tools::Compatibility::DEPRECATED_NAMES.keys
      result = Tools::Compatibility.resolve(names)
      names.each_with_index do |old, i|
        expect(result[i]).to eq(Tools::Compatibility::DEPRECATED_NAMES[old])
      end
    end
  end

  context "resolve_single" do
    it "maps a single deprecated name to its current name" do
      expect(Tools::Compatibility.resolve_single("read_text_file")).to eq("read_text")
    end

    it "returns the name unchanged when it is not deprecated" do
      expect(Tools::Compatibility.resolve_single("find")).to eq("find")
    end
  end

  context "any_deprecated?" do
    it "returns true when any name is deprecated" do
      expect(Tools::Compatibility.any_deprecated?(["find", "read_text_file"])).to be_true
    end

    it "returns false when no names are deprecated" do
      expect(Tools::Compatibility.any_deprecated?(["find", "search", "date"])).to be_false
    end
  end

  context "deprecated?" do
    it "returns true for a deprecated name" do
      expect(Tools::Compatibility.deprecated?("read_text_file")).to be_true
    end

    it "returns false for a current name" do
      expect(Tools::Compatibility.deprecated?("read_text")).to be_false
    end
  end

  context "old_name_for?" do
    it "returns the old name for a current name" do
      expect(Tools::Compatibility.old_name_for?("read_text")).to eq("read_text_file")
    end

    it "returns nil for a name with no deprecated predecessor" do
      expect(Tools::Compatibility.old_name_for?("install_tools")).to be_nil
    end
  end

  context "deprecation_table" do
    it "contains the markdown table headers" do
      table = Tools::Compatibility.deprecation_table
      expect(table).to contain("| Deprecated | Current |")
      expect(table).to contain("|---|---|")
    end

    it "contains at least one mapping" do
      table = Tools::Compatibility.deprecation_table
      expect(table).to contain("`read_text_file` | `read_text`")
    end
  end

  context "warned? / mark_warned!" do
    # NOTE: @@warned is persistent class-level state and the suite runs with
    # config.randomize, so we cannot assert an "initially false" value in a
    # repeatable way -- once any test calls mark_warned!, the flag stays true
    # for the rest of the process. We therefore only assert the transition to
    # true, which is deterministic regardless of test order.
    it "is true after mark_warned! has been called" do
      Tools::Compatibility.mark_warned!
      expect(Tools::Compatibility.warned?).to be_true
    end
  end
end
