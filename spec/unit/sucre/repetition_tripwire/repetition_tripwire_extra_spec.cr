require "../../../spec_helper"

# Additional specs covering the two axes the first suite does not: the streaming
# (many-small-fragments) usage pattern the harness actually uses, and false-
# positive resistance on realistic content. Merge into the existing file or keep
# alongside it.
Spectator.describe RepetitionTripwire do
  # A deterministic, non-periodic hex stream (seeded PRNG) — stands in for the
  # structured, low-diversity content a tool-argument stream legitimately emits.
  def varied_hex(n : Int32) : String
    String.build do |s|
      r = Random.new(42)
      n.times { s << "0123456789abcdef"[r.rand(16)] }
    end
  end

  describe "Streaming (fragmented) feeds" do
    it "accumulates a run across many single-character feeds" do
      wire = described_class.new # default max_run 100
      300.times { wire << "!" }

      expect(wire.tripped?).to be_true
      expect(wire.trip.not_nil!.check).to eq(RepetitionTripwire::Check::Run)
      # latches at the threshold; later feeds are no-ops
      expect(wire.chars_seen).to eq(100)
    end

    it "detects a period split across fragments fed one character at a time" do
      wire = described_class.new(min_chars: 50, check_every: 10, min_period_span: 20)
      ("abc" * 30).each_char { |c| wire << c.to_s }

      expect(wire.tripped?).to be_true
      expect(wire.trip.not_nil!.check).to eq(RepetitionTripwire::Check::Period)
    end

    it "does not reset a run across an empty feed" do
      wire = described_class.new(max_run: 10)
      wire << ("a" * 9)
      wire << ""
      wire << "a"

      expect(wire.tripped?).to be_true
      expect(wire.trip.not_nil!.check).to eq(RepetitionTripwire::Check::Run)
    end
  end

  describe "False-positive resistance on realistic content" do
    it "stays clean on varied prose past min_chars" do
      prose = "The explore worker claimed the newest open intent, ran a ruby " \
              "script to compute the value, recorded one confirmed fact, and " \
              "marked the intent done. Reason re-read the whole board to decide " \
              "whether the goal was satisfied or a new direction was warranted."
      wire = described_class.new
      wire << prose
      expect(wire.tripped?).to be_false
    end

    it "stays clean on realistic board text" do
      board = String.build do |s|
        s << "# Cairn board: t\nGOAL: twelve squares\n"
        s << "FACT origin [from=]: record squares 1..12\n"
        (1..12).each { |n| s << "FACT f#{n.to_s.rjust(3, '0')} [from=origin]: #{n} squared is #{n * n}\n" }
        s << "<END>\n"
      end
      wire = described_class.new
      wire << board
      expect(wire.tripped?).to be_false
    end

    it "stays clean on varied hex under default config" do
      wire = described_class.new
      wire << varied_hex(1500)
      expect(wire.tripped?).to be_false
    end

    it "stays clean on a long low-diversity tool-argument run with a loosened config" do
      # Recommended tool-argument config: run allowed to be long, period off.
      wire = described_class.new(max_run: 800, max_period: 0, check_diversity: false)
      wire << ("0" * 400) # 400 zeros: legitimate padding, below the raised run cap
      expect(wire.tripped?).to be_false
    end
  end

  describe "Unicode / multi-byte characters" do
    it "counts a run of a multi-byte character as characters, not bytes" do
      wire = described_class.new(max_run: 10)
      wire << ("é" * 10) # 2 bytes each; must trip at 10 chars, not 20 bytes
      expect(wire.tripped?).to be_true
      expect(wire.trip.not_nil!.check).to eq(RepetitionTripwire::Check::Run)
    end

    it "detects a multi-byte period" do
      wire = described_class.new(min_chars: 20, check_every: 5, min_period_span: 20, max_period: 8)
      wire << ("日本語" * 15)
      expect(wire.tripped?).to be_true
      expect(wire.trip.not_nil!.check).to eq(RepetitionTripwire::Check::Period)
    end
  end

  describe "Diversity disabled by default (meaningful)" do
    it "does not trip on low-diversity input when diversity is off and nothing else can fire" do
      # Suppress Run and Period so diversity is the only check that could fire.
      wire = described_class.new(max_run: 1000, min_period_span: 10_000,
        diversity_window: 50, min_diversity: 0.5, min_chars: 50, check_every: 10)
      wire << ("ab" * 50) # 2 distinct / 100 = 0.02, well under 0.5 — would trip if enabled
      expect(wire.tripped?).to be_false
    end
  end

  describe "Window eviction" do
    it "counts every character and stays clean on varied input past window_size" do
      wire = described_class.new # window_size 2048
      wire << varied_hex(3000)
      expect(wire.tripped?).to be_false
      expect(wire.chars_seen).to eq(3000)
    end

    it "detects a loop that appears only after the window has churned" do
      wire = described_class.new
      wire << varied_hex(2048) # fill with varied content
      expect(wire.tripped?).to be_false
      wire << ("abc" * 40) # recent window becomes periodic
      expect(wire.tripped?).to be_true
      expect(wire.trip.not_nil!.check).to eq(RepetitionTripwire::Check::Period)
    end
  end

  describe "Period thresholds (boundaries)" do
    let(wire) do
      described_class.new(min_chars: 10, check_every: 5, max_period: 32,
        min_cycles: 4, min_period_span: 20)
    end

    it "does not trip when the periodic span is just under min_period_span" do
      wire << ("abc" * 6) # span 18 < 20
      expect(wire.tripped?).to be_false
    end

    it "trips when the periodic span reaches min_period_span" do
      wire << ("abc" * 7) # span 21 >= 20
      expect(wire.tripped?).to be_true
      expect(wire.trip.not_nil!.check).to eq(RepetitionTripwire::Check::Period)
    end
  end
end
