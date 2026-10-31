require "spectator"
require "http/client"
require "wiretap"

require "../src/*"
require "../src/sucre/**"

require "./support/web_tool_helpers"
require "./support/file_tool_helpers"
require "./support/llm_helpers"

Spectator.configure do |config|
  config.fail_blank # Fail on no tests.
  config.randomize  # Randomize test order.
end

# Wiretap records LLM HTTP transcripts on the first local run and replays
# them offline afterwards (and strictly in CI, where no live calls are made).
Wiretap.configure do |c|
  c.transcript_dir = "spec/transcripts"
  c.record_mode = ENV["CI"]? ? :none : :once
end
