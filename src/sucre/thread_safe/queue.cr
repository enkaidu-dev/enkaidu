require "sync/exclusive"

module TS
  # A thread-safe queue backed by an exclusive lock on the queue array
  class Queue(T)
    private getter ex_queue : Sync::Exclusive(Array(T))

    def initialize
      @ex_queue = Sync::Exclusive(Array(T)).new([] of T)
    end

    # Add item to the end of the queue
    def add(value : T) : self
      ex_queue.lock do |queue|
        queue << value
      end
      self
    end

    # :ditto:
    def <<(value : T) : self
      add(value)
    end

    # Return `true` if queue is empty
    def empty? : Bool
      ex_queue.lock(&.empty?)
    end

    # Shift item from the top of the queue, or `nil?` if empty
    def shift? : T?
      ex_queue.lock(&.shift?)
    end
  end
end
