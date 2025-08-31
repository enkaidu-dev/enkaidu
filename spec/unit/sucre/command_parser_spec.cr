require "../../spec_helper"

Spectator.describe CommandParser do
  let(command) { "first 'second' third=value fourth='spaced out'" }
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
          expect(parser.arg_named?("fourth")).to eq("'spaced out'")
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
      context "at valid index" do
        it "succeeds" do
          expect(parser.arg_at?(0)).to eq("first")
        end
      end
      context "at index of named arg" do
        it "fails" do
          expect(parser.arg_at?(2)).to be(nil)
        end
      end
      context "at negative index" do
        it "return from last positional arg" do
          expect(parser.arg_at?(-1)).to eq("second")
        end
      end
      context "at beyond last arg" do
        it "fails" do
          expect(parser.arg_at?(3)).to be(nil)
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
        subject { parser.expect?(String, String, third: String, fourth: String) }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "union types" do
        subject { parser.expect?(String?, String | Float32, third: String?, fourth: String) }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "with values" do
        subject { parser.expect?("first", "second", third: "value", fourth: "'spaced out'") }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "with value lists" do
        subject { parser.expect?(["first"], ["second", "other"], third: ["value", "other"], fourth: ["'spaced out'"]) }
        it "succeeds" do
          is_expected.to be_true
        end
      end

      context "with regex" do
        subject { parser.expect?(/fir\w+/, /\w+/, third: "value", fourth: "'spaced out'") }
        it "succeeds" do
          is_expected.to be_true
        end
      end
    end

    context "with less args" do
      subject { parser.expect?(String, String, third: String) }
      it "fails" do
        is_expected.to be_false
      end
    end

    context "with extra" do
      context "positional arg" do
        subject { parser.expect?(String, String, String, third: String, fourth: String) }
        it "fails" do
          is_expected.to be_false
        end
      end

      context "named arg" do
        subject { parser.expect?(String, String, third: String, fourth: String, fifth: String) }
        it "fails" do
          is_expected.to be_false
        end
      end
    end
  end
end
