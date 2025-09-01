require "../../spec_helper"

Spectator.describe CommandParser do
  let(command) { "first 'second' [free standing] arr=[ content1 'content 2'] third=value fourth='spaced out'" }
  let(parser) { described_class.new(command) }

  describe "#arg_named?" do
    context "with named arg: " do
      context "\"third\"" do
        it "succeeds" do
          expect(parser.arg_named?("third")).to eq("value")
        end
      end
      context "\"fourth\"" do
        it "succeeds" do
          expect(parser.arg_named?("fourth")).to eq("spaced out")
        end
      end
      context "\"arr\"" do
        it "succeeds" do
          expect(parser.arg_named?("arr")).to eq(["content1", "content 2"])
        end
      end
      context "\"zaboomafoo\"" do
        it "fails" do
          expect(parser.arg_named?("zaboomafoo")).to be(nil)
        end
      end
    end
  end

  describe "#arg_at?" do
    context "with positional args" do
      context "at index 0" do
        it "succeeds" do
          expect(parser.arg_at?(0)).to eq("first")
        end
      end
      context "at index 1" do
        it "succeeds" do
          expect(parser.arg_at?(1)).to eq("second")
        end
      end
      context "at index 2" do
        it "succeeds" do
          expect(parser.arg_at?(2)).to eq(["free", "standing"])
        end
      end
      context "at index of named arg" do
        it "fails" do
          expect(parser.arg_at?(3)).to be(nil)
        end
      end
      context "at negative index" do
        it "return from last positional arg" do
          expect(parser.arg_at?(-1)).to eq(["free", "standing"])
        end
      end
      context "at beyond last arg" do
        it "fails" do
          expect(parser.arg_at?(4)).to be(nil)
        end
      end
    end
  end

  describe "#expect?" do
    context "with single quotes" do
      context "around args" do
        let(command) { "/save 'spaced name'" }
        subject { parser.expect?(String, String) }
        it "succeeds" do
          is_expected.to be_true
        end

        it "removes quotes" do
          parser.arg_at?(1) == "spaced name"
        end
      end

      context "within args" do
        let(command) { "/save name='spaced name'" }
        subject { parser.expect?(String, name: String) }
        it "succeeds" do
          is_expected.to be_true
        end

        it "removes quotes" do
          parser.arg_named?("name") == "spaced name"
        end
      end
    end

    context "matching" do
      context "exact types" do
        subject { parser.expect?(String, String, Array(String), arr: Array(String), third: String, fourth: String) }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "union types" do
        subject { parser.expect?(String?, String | Float32, Array(String), arr: Array(String), third: String?, fourth: String) }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "exact values" do
        subject { parser.expect?("first", "second", ["free", "standing"], arr: Array(String), third: "value", fourth: "spaced out") }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "membership in value lists" do
        subject { parser.expect?(["first"], ["second", "other"], [["free", "standing"], ["some", "other"]], arr: Array(String), third: ["value", "other"], fourth: ["spaced out"]) }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "against regex" do
        subject { parser.expect?(/fir\w+/, /\w+/, Array(String), arr: Array(String), third: "value", fourth: "spaced out") }
        it "succeeds" do
          is_expected.to be_true
        end
      end
    end

    context "when less args" do
      subject { parser.expect?(String, String, third: String) }
      it "fails" do
        is_expected.to be_false
      end
    end

    context "when extra" do
      context "positional arg" do
        subject { parser.expect?(String, String, String, Array(String), arr: Array(String), third: String, fourth: String) }
        it "fails" do
          is_expected.to be_false
        end
      end

      context "named arg" do
        subject { parser.expect?(String, String, Array(String), arr: Array(String), third: String, fourth: String, fifth: String) }
        it "fails" do
          is_expected.to be_false
        end
      end
    end
  end
end
