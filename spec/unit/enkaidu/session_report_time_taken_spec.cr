require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

class TimeElapsedProbeRenderer < EnkaiduWiretapTestRenderer
  record TimeElapsedCall, duration : Time::Span, label : String?

  getter time_elapsed_calls = [] of TimeElapsedCall

  def time_elapsed(duration : Time::Span, label : String? = nil) : Nil
    @time_elapsed_calls << TimeElapsedCall.new(duration, label)
  end
end

class ReportTimeTakenProbeSession < Enkaidu::Session
  def report_time_taken_for_test(prefix : String? = nil, &)
    report_time_taken(prefix) { yield }
  end
end

Spectator.describe "Enkaidu::Session report_time_taken" do
  include EnkaiduSessionWiretapHelpers

  it "calls renderer.time_elapsed with nil label when no prefix is given" do
    with_ollama_envs do
      renderer = TimeElapsedProbeRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = ReportTimeTakenProbeSession.new(renderer, options)

      session.report_time_taken_for_test do
      end

      expect(renderer.time_elapsed_calls.size).to eq(1)
      expect(renderer.time_elapsed_calls.first.label).to be_nil
    end
  end

  it "calls renderer.time_elapsed with the given prefix as label" do
    with_ollama_envs do
      renderer = TimeElapsedProbeRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = ReportTimeTakenProbeSession.new(renderer, options)

      session.report_time_taken_for_test("Total ") do
      end

      expect(renderer.time_elapsed_calls.size).to eq(1)
      expect(renderer.time_elapsed_calls.first.label).to eq("Total ")
    end
  end

  it "reports a non-negative duration" do
    with_ollama_envs do
      renderer = TimeElapsedProbeRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = ReportTimeTakenProbeSession.new(renderer, options)

      session.report_time_taken_for_test do
      end

      expect(renderer.time_elapsed_calls.first.duration.to_i).to be >= 0
    end
  end

  it "executes the block" do
    with_ollama_envs do
      renderer = TimeElapsedProbeRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      session = ReportTimeTakenProbeSession.new(renderer, options)

      executed = false
      session.report_time_taken_for_test do
        executed = true
      end

      expect(executed).to be true
    end
  end
end
