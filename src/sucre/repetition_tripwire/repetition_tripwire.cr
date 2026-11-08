# Streaming repetition tripwire for degenerate model output.
#
# Detects a generation that has collapsed into a loop — one character repeated
# (`!!!!!!…`), a short cycle (`abcabc…`), or a repeated phrase — as text streams
# in, so a stuck worker can be aborted in a fraction of a second of wasted
# generation rather than waiting for a token or time cap to fire.
#
# This is deliberately NOT Shannon entropy. Entropy misses cyclic and phrase
# loops (whose character distribution looks healthy) and false-alarms on
# legitimate low-diversity text (hex, base64). It instead looks for repetition
# directly, which is the actual failure shape and is nearly free of false
# positives on real output.
#
# Feed each generated fragment with `#<<` as it arrives, then check `#tripped?`.
# Run ONE instance per independent output stream (response text, reasoning text,
# tool-call arguments); never merge streams into a single monitor — merging both
# hides a loop in one channel and invents seams between channels. Do not
# normalise fragments before feeding: runs of whitespace or newlines are
# themselves signals. Once tripped, the monitor latches.
#
# ```
# mon = RepetitionTripwire.new
# stream.each_fragment do |frag|
#   mon << frag
#   break if mon.tripped?
# end
# if t = mon.trip
#   abort_worker(reason: t.message) # t : RepetitionTripwire::Trip
# end
# ```
class RepetitionTripwire
  # Which check fired. `Run` and `Period` are high-confidence; `Diversity` is a
  # loose backstop and is off by default.
  enum Check
    Run
    Period
    Diversity
  end

  # Why the tripwire fired. `message` is a short, loggable explanation suitable
  # for recording on an aborted step.
  record Trip, check : Check, message : String

  # - *window_size*: trailing characters examined by the window checks.
  # - *check_every*: run the window checks once per this many new characters
  #   (the cheap per-character run check is always on).
  # - *min_chars*: never trip the window checks before this many characters seen,
  #   so short legitimate outputs cannot trip.
  # - *max_run*: trip when this many identical characters appear consecutively.
  # - *max_period*: longest repeating unit the period check searches for.
  # - *min_cycles*: a period must repeat at least this many times to trip.
  # - *min_period_span*: a periodic suffix must also be at least this many
  #   characters long, so a brief alternation cannot trip.
  # - *check_diversity*: enable the low-confidence distinct-character backstop.
  # - *min_diversity* / *diversity_window*: trip if distinct/length over the
  #   window falls below *min_diversity*, once the window holds *diversity_window*
  #   characters. Prose/reasoning streams only — leave off for tool arguments,
  #   where hex and base64 legitimately have few distinct characters.
  def initialize(
    @window_size : Int32 = 2048,
    @check_every : Int32 = 96,
    @min_chars : Int32 = 200,
    @max_run : Int32 = 100,
    @max_period : Int32 = 128,
    @min_cycles : Int32 = 4,
    @min_period_span : Int32 = 60,
    @check_diversity : Bool = false,
    @min_diversity : Float64 = 0.03,
    @diversity_window : Int32 = 500,
  )
    @window = Deque(Char).new(@window_size)
    @total = 0_i64
    @since_check = 0
    @run_char = '\0'
    @run_len = 0
    @trip = nil
  end

  # Feed a fragment of generated text. Returns self so feeds can chain. Cheap
  # once tripped (returns immediately).
  def <<(text : String) : self
    return self if @trip
    text.each_char do |c|
      push(c)
      break if @trip
    end
    maybe_window_checks unless @trip
    self
  end

  # :ditto:
  def feed(text : String) : self
    self << text
  end

  # Whether the stream has been judged degenerate. Latches once true.
  def tripped? : Bool
    !@trip.nil?
  end

  # The trip record once tripped, else nil.
  def trip : Trip?
    @trip
  end

  # Total characters fed so far.
  def chars_seen : Int64
    @total
  end

  # Clear all state to reuse the instance for a fresh stream.
  def reset : Nil
    @window.clear
    @total = 0_i64
    @since_check = 0
    @run_char = '\0'
    @run_len = 0
    @trip = nil
  end

  # Append one character to the bounded window and update the always-on run
  # check (consecutive identical characters).
  private def push(c : Char) : Nil
    @window.push(c)
    @window.shift if @window.size > @window_size
    @total += 1
    @since_check += 1

    if c == @run_char
      @run_len += 1
    else
      @run_char = c
      @run_len = 1
    end

    if @run_len >= @max_run
      @trip = Trip.new(Check::Run, "#{@run_len} consecutive #{c.inspect}")
    end
  end

  # Run the window checks at the configured cadence, gated by *min_chars*.
  private def maybe_window_checks : Nil
    return if @since_check < @check_every
    @since_check = 0
    return if @total < @min_chars
    check_period
    check_diversity if @trip.nil? && @check_diversity
  end

  # Trip when a suffix of the window is a short unit repeated. For each period
  # p >= 2 (p == 1 is the run check), count how far back the window stays
  # periodic with that period; trip on the smallest p whose periodic suffix is
  # both long enough in absolute terms and repeats enough times.
  private def check_period : Nil
    size = @window.size
    p = 2
    while p <= @max_period
      matched = 0
      i = size - 1
      while i >= p && @window[i] == @window[i - p]
        matched += 1
        i -= 1
      end
      if matched > 0
        span = matched + p
        if span >= @min_period_span && span >= p * @min_cycles
          unit = String.build { |s| (size - p...size).each { |j| s << @window[j] } }
          @trip = Trip.new(Check::Period, "#{span // p}x repetition of #{unit.inspect}")
          return
        end
      end
      p += 1
    end
  end

  # Loose backstop: trip when the window has collapsed to a tiny alphabet even
  # without a clean period. Off by default; prose/reasoning streams only.
  private def check_diversity : Nil
    size = @window.size
    return if size < @diversity_window
    distinct = Set(Char).new
    @window.each { |c| distinct << c }
    ratio = distinct.size.to_f / size
    if ratio < @min_diversity
      @trip = Trip.new(Check::Diversity, "#{distinct.size} distinct chars over #{size}")
    end
  end
end
