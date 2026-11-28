require "../../spec_helper"

class ProgressSpy < Enkaidu::Progress
  getter label_set_calls = [] of String
  getter start_calls = 0
  getter stop_calls = 0

  def initialize
    super("initial")
  end

  def label=(val : String)
    @label = val
    @label_set_calls << val
  end

  def start : Nil
    @start_calls += 1
  end

  def stop : Nil
    @stop_calls += 1
  end
end

class ProgressLabelProbeSession < Enkaidu::Session
  def self.for_test : self
    obj = uninitialized(ProgressLabelProbeSession)
    obj
  end

  def check_progress_for_test(event : LLM::ChatEvent, progress : Enkaidu::Progress) : Nil
    check_and_show_progress(event, progress)
  end
end

Spectator.describe "Enkaidu::Session#check_and_show_progress" do
  it "sets label to Receiving... and calls start on ReceivingToolCall event" do
    session = ProgressLabelProbeSession.for_test
    spy = ProgressSpy.new

    event = {type: LLM::Event::ReceivingToolCall, content: JSON::Any.new("some_tool")}
    session.check_progress_for_test(event, spy)

    expect(spy.start_calls).to eq(1)
    expect(spy.stop_calls).to eq(0)
    expect(spy.label_set_calls.size).to eq(1)
    expect(spy.label_set_calls.first).to start_with("Receiving")
  end

  it "sets label to Waiting and calls start on WarnTooManyRequestsDelay event" do
    session = ProgressLabelProbeSession.for_test
    spy = ProgressSpy.new

    event = {type: LLM::Event::WarnTooManyRequestsDelay, content: JSON::Any.new("rate limited")}
    session.check_progress_for_test(event, spy)

    expect(spy.start_calls).to eq(1)
    expect(spy.stop_calls).to eq(0)
    expect(spy.label_set_calls).to eq(["Waiting"])
  end

  it "calls stop and leaves label unchanged on non-matching event" do
    session = ProgressLabelProbeSession.for_test
    spy = ProgressSpy.new

    event = {type: LLM::Event::Text, content: JSON::Any.new("hello")}
    session.check_progress_for_test(event, spy)

    expect(spy.start_calls).to eq(0)
    expect(spy.stop_calls).to eq(1)
    expect(spy.label_set_calls).to be_empty
  end
end
