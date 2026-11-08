require "../../spec_helper"

Spectator.describe Enkaidu::InterruptHandler do
  before_each do
    Enkaidu::InterruptHandler.end_turn
  end

  after_each do
    Enkaidu::InterruptHandler.end_turn
  end

  describe ".trigger!" do
    it "returns false when no turn is active" do
      expect(Enkaidu::InterruptHandler.trigger!).to be_false
      expect(Enkaidu::InterruptHandler.interrupted?).to be_false
    end

    it "sets interrupted state and returns true when a turn is active" do
      Enkaidu::InterruptHandler.begin_turn
      expect(Enkaidu::InterruptHandler.active?).to be_true

      expect(Enkaidu::InterruptHandler.trigger!).to be_true
      expect(Enkaidu::InterruptHandler.interrupted?).to be_true
    end
  end

  describe ".check!" do
    it "raises UserInterruptError when interrupted flag is set and resets flag" do
      Enkaidu::InterruptHandler.begin_turn
      Enkaidu::InterruptHandler.trigger!

      expect do
        Enkaidu::InterruptHandler.check!
      end.to raise_error(Enkaidu::InterruptHandler::UserInterruptError)

      # Flag should be reset after raising
      expect(Enkaidu::InterruptHandler.interrupted?).to be_false
    end

    it "does not raise when not interrupted" do
      Enkaidu::InterruptHandler.begin_turn
      expect do
        Enkaidu::InterruptHandler.check!
      end.not_to raise_error
    end
  end
end
