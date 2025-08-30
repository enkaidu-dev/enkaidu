require "../../spec_helper"

Spectator.describe CommandParser do
  let(command_parts) { ["first", "second", ["third", "value"], ["fourth", "'spaced out'"]] }
  let(command) { join_parts(command_parts) }
  let(parser) { described_class.new(command) }

  # Used to construct a command so we can verify command parser
  # results
  private def join_parts(parts)
    (parts.map do |arg|
      if arg.is_a? Array
        arg.join('=')
      else
        arg
      end
    end).join(' ')
  end

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

    context "with types" do
      subject { parser.expect?(String, String, third: String, fourth: String) }
      it "succeeds" do
        is_expected.to be_true
      end
    end

    context "with values" do
      subject { parser.expect?(command_parts[0], command_parts[1],
        third: command_parts[2].as(Array).last,
        fourth: command_parts[3].as(Array).last) }
      it "succeeds" do
        is_expected.to be_true
      end
    end

    context "with value lists" do
      subject { parser.expect?([command_parts[0]], [command_parts[1], "other"],
        third: command_parts[2],
        fourth: command_parts[3]) }
      it "succeeds" do
        is_expected.to be_true
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
