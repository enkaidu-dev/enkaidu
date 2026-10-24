require "colorize"

module Enkaidu
  class Progress
    TICK = 60.milliseconds

    FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
    # FRAMES = %w[\\ | / -]

    property label : String
    property lines : Int32

    getter? running

    def initialize(@label : String, @lines = 0, @io : IO = STDERR)
      @stop = Channel(Nil).new
      @drained = Channel(Nil).new
      @running = false
      @width = 0
    end

    def start : Nil
      return if @running || !@io.tty?

      @running = true
      started = Time.instant

      spawn do
        frame = 0
        loop do
          select # select runs all conditions and exits on first to return
          when @stop.receive?
            break
          when timeout(TICK)
            draw(FRAMES[frame % FRAMES.size], Time.instant - started)
            frame += 1
          end
        end
        erase
        @drained.send(nil)
      end
    end

    def stop : Nil
      return unless @running

      @running = false
      @stop.send(nil)
      @drained.receive?
    end

    private def draw(frame : String, elapsed : Time::Span) : Nil
      line = "#{frame} #{@label}#{" (#{lines} lines)" if lines.positive?}… #{elapsed.total_seconds.to_i}s"
      @io.print("\r#{line}".colorize.light_gray)
      @io.flush
      @width = line.size
    end

    private def erase : Nil
      return if @width.zero?
      @io.print("\r#{" " * @width}\r")
      @io.flush
      @width = 0
    end
  end
end
