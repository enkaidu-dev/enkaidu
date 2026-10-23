require "spectator"

require "../src/*"
require "../src/sucre/**"

require "./support/web_tool_helpers"

Spectator.configure do |config|
  config.fail_blank # Fail on no tests.
  config.randomize  # Randomize test order.
end
