require "../../spec_helper"

class VerifyLoadedSessionUnitSession < Enkaidu::Session
  def verify_loaded_session_nil_for_test : Nil
    verify_loaded_session(nil)
  end

  def self.run_verify_loaded_session_nil : Nil
    session = uninitialized self
    session.verify_loaded_session_nil_for_test
  end
end

Spectator.describe "Enkaidu::Session verify_loaded_session(nil)" do
  it "does nothing" do
    VerifyLoadedSessionUnitSession.run_verify_loaded_session_nil
    expect(true).to be_true
  end
end
