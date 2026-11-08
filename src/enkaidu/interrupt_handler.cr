require "atomic"

module Enkaidu
  # `InterruptHandler` coordinates signal interrupts (such as Ctrl+C / SIGINT)
  # between the process signal handler (`Process.on_terminate`) and active session execution.
  module InterruptHandler
    class UserInterruptError < Exception; end

    @@active = false
    @@interrupted = Atomic(Bool).new(false)

    # Signal the start of a turn in session processing.
    def self.begin_turn : Nil
      @@interrupted.set(false)
      @@active = true
    end

    # Signal the end of a turn in session processing.
    def self.end_turn : Nil
      @@active = false
      @@interrupted.set(false)
    end

    # Returns true if a turn is currently in progress.
    def self.active? : Bool
      @@active
    end

    # Called by `Process.on_terminate` when SIGINT is caught.
    # Returns true if an active turn was flagged for interrupt,
    # or false if no turn is active (allowing the process to exit).
    def self.trigger! : Bool
      if @@active
        @@interrupted.set(true)
        true
      else
        false
      end
    end

    # Returns true if an interrupt was requested.
    def self.interrupted? : Bool
      @@interrupted.get
    end

    # Checks if an interrupt was requested and raises `UserInterruptError` if so.
    def self.check! : Nil
      if interrupted?
        @@interrupted.set(false)
        raise UserInterruptError.new("Response interrupted by user.")
      end
    end
  end
end
