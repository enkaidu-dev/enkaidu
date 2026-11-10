require "../../spec_helper"

Spectator.describe Enkaidu::InterruptHandler do
  let(handler) { Enkaidu::InterruptHandler.new }

  describe "#trigger!" do
    it "returns false when no turn is active" do
      expect(handler.trigger!).to be_false
      expect(handler.interrupted?).to be_false
    end

    it "sets interrupted state and returns true when a turn is active" do
      handler.begin_turn
      expect(handler.active?).to be_true

      expect(handler.trigger!).to be_true
      expect(handler.interrupted?).to be_true
    end
  end

  describe "#check!" do
    it "raises UserInterruptError when interrupted flag is set and resets flag" do
      handler.begin_turn
      handler.trigger!

      expect do
        handler.check!
      end.to raise_error(Enkaidu::InterruptHandler::UserInterruptError)

      # Flag should be reset after raising
      expect(handler.interrupted?).to be_false
    end

    it "does not raise when not interrupted" do
      handler.begin_turn
      expect do
        handler.check!
      end.not_to raise_error
    end
  end

  describe "nested turns" do
    it "maintains active state until outer turn ends" do
      handler.begin_turn # Outer (depth 1)
      expect(handler.depth).to eq(1)

      handler.begin_turn # Nested (depth 2)
      expect(handler.depth).to eq(2)
      expect(handler.active?).to be_true

      handler.end_turn # Nested finishes (depth 1)
      expect(handler.depth).to eq(1)
      expect(handler.active?).to be_true

      expect(handler.trigger!).to be_true

      handler.end_turn # Outer finishes (depth 0)
      expect(handler.depth).to eq(0)
      expect(handler.active?).to be_false
    end
  end

  describe "session stack isolation" do
    it "isolates interrupts between separate handlers" do
      handler1 = Enkaidu::InterruptHandler.new
      handler2 = Enkaidu::InterruptHandler.new

      handler1.begin_turn
      handler2.begin_turn

      expect(handler1.trigger!).to be_true

      expect(handler1.interrupted?).to be_true
      expect(handler2.interrupted?).to be_false
    end
  end
end
