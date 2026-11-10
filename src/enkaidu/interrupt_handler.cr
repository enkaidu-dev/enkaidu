require "atomic"

module Enkaidu
  # `InterruptHandler` coordinates signal interrupts (such as Ctrl+C / SIGINT)
  # between process/web UI termination requests and active session stack execution.
  class InterruptHandler
    class UserInterruptError < Exception; end

    class TripwireInterruptError < UserInterruptError; end

    DEFAULT_INTERRUPT_MSG = "Response interrupted by user."
    DEFAULT_CANCEL_MSG    = "Execution cancelled."

    private getter depth_counter = Atomic(Int32).new(0)
    private getter interrupted_flag = Atomic(Bool).new(false)

    def initialize
    end

    # Signal the start of a turn in session processing.
    def begin_turn : Nil
      interrupted_flag.set(false)
      depth_counter.add(1)
    end

    # Signal the end of a turn in session processing.
    def end_turn : Nil
      if depth_counter.get > 0
        depth_counter.sub(1)
      end
      if depth_counter.get == 0
        interrupted_flag.set(false)
      end
    end

    # Reset interrupt handler state.
    def reset! : Nil
      depth_counter.set(0)
      interrupted_flag.set(false)
    end

    # Returns true if a turn is currently in progress.
    def active? : Bool
      depth_counter.get > 0
    end

    # Returns current nesting depth of active turns.
    def depth : Int32
      depth_counter.get
    end

    # Flag an interrupt on this active turn.
    # Returns true if an active turn was flagged for interrupt,
    # or false if no turn is active.
    def trigger! : Bool
      if active?
        interrupted_flag.set(true)
        true
      else
        false
      end
    end

    # Returns true if an interrupt was requested.
    def interrupted? : Bool
      interrupted_flag.get
    end

    # Checks if an interrupt was requested and raises `UserInterruptError` if so.
    def check! : Nil
      if interrupted?
        interrupted_flag.set(false)
        raise UserInterruptError.new(DEFAULT_INTERRUPT_MSG)
      end
    end
  end
end
