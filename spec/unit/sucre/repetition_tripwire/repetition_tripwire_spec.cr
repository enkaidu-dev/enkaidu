require "../../../spec_helper"

Spectator.describe RepetitionTripwire do
  subject(tripwire) { described_class.new }

  it "starts in a non-tripped state" do
    expect(tripwire.tripped?).to be_false
    expect(tripwire.trip).to be_nil
    expect(tripwire.chars_seen).to eq(0)
  end

  it "tracks total characters seen across multiple feeds" do
    tripwire << "Hello "
    tripwire.feed("World!")

    expect(tripwire.chars_seen).to eq(12)
  end

  describe "Run check" do
    let(tripwire) { described_class.new(max_run: 10) }

    it "does not trip under max_run" do
      tripwire << "a" * 9
      expect(tripwire.tripped?).to be_false
    end

    it "trips when consecutive character count reaches max_run" do
      tripwire << "a" * 10

      expect(tripwire.tripped?).to be_true
      trip = tripwire.trip.not_nil!
      expect(trip.check).to eq(RepetitionTripwire::Check::Run)
      expect(trip.message).to contain("10 consecutive 'a'")
    end

    it "resets run count when character changes" do
      tripwire << ("a" * 9) + "b" + ("a" * 9)
      expect(tripwire.tripped?).to be_false
    end
  end

  describe "Period check" do
    let(tripwire) do
      described_class.new(
        min_chars: 50,
        check_every: 10,
        max_period: 32,
        min_cycles: 4,
        min_period_span: 20
      )
    end

    it "does not trip before min_chars is reached" do
      # Span 30 > 20 and 10 cycles > 4, but total chars 30 < min_chars 50
      tripwire << "abc" * 10
      expect(tripwire.tripped?).to be_false
    end

    it "trips when a repeating pattern spans enough cycles and length after min_chars" do
      # Feed a repeating pattern past min_chars (50) and past check_every (10)
      tripwire << "abc" * 30

      expect(tripwire.tripped?).to be_true
      trip = tripwire.trip.not_nil!
      expect(trip.check).to eq(RepetitionTripwire::Check::Period)
      expect(trip.message).to contain("repetition of \"abc\"")
    end

    it "does not trip on non-repeating varied text" do
      tripwire << "The quick brown fox jumps over the lazy dog repeatedly without cycling into a strict loop."
      expect(tripwire.tripped?).to be_false
    end
  end

  describe "Diversity check" do
    let(tripwire) do
      described_class.new(
        check_diversity: true,
        diversity_window: 50,
        min_diversity: 0.1,
        check_every: 10,
        min_chars: 50,
        min_period_span: 1000
      )
    end

    it "is disabled by default" do
      default_wire = described_class.new(diversity_window: 50, min_chars: 50, check_every: 10)
      # Feed text with only 2 distinct chars over 60 chars (diversity = 2/50 = 0.04)
      default_wire << ("ab" * 25)
      # Run/period might not trip depending on settings, but diversity shouldn't trip
      if default_wire.tripped?
        expect(default_wire.trip.not_nil!.check).to_not eq(RepetitionTripwire::Check::Diversity)
      end
    end

    it "trips when unique character ratio falls below threshold" do
      # Construct input with 2 distinct chars 'a' and 'b' arranged to avoid short period trip if needed,
      # e.g., irregular repetition of 'a' and 'b'
      pattern = "aaaaabbbbb" * 6 # 60 chars total, distinct chars = 2 ('a', 'b'), ratio 2/50 = 0.04 < 0.1
      tripwire << pattern

      expect(tripwire.tripped?).to be_true
      trip = tripwire.trip.not_nil!
      expect(trip.check).to eq(RepetitionTripwire::Check::Diversity)
      expect(trip.message).to contain("distinct chars over")
    end
  end

  describe "Latched state and post-trip behavior" do
    let(tripwire) { described_class.new(max_run: 5) }

    it "latches once tripped and makes subsequent feeds no-ops" do
      tripwire << "aaaaa"
      expect(tripwire.tripped?).to be_true
      seen_at_trip = tripwire.chars_seen

      tripwire << "bbbbb"
      expect(tripwire.chars_seen).to eq(seen_at_trip)
      expect(tripwire.trip.not_nil!.message).to contain("5 consecutive 'a'")
    end
  end

  describe "#reset" do
    let(tripwire) { described_class.new(max_run: 5) }

    it "restores the tripwire to its initial clean state" do
      tripwire << "aaaaa"
      expect(tripwire.tripped?).to be_true

      tripwire.reset

      expect(tripwire.tripped?).to be_false
      expect(tripwire.trip).to be_nil
      expect(tripwire.chars_seen).to eq(0)

      tripwire << "hello"
      expect(tripwire.tripped?).to be_false
      expect(tripwire.chars_seen).to eq(5)
    end
  end
end
