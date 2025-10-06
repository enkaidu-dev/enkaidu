require "../content"

require "./prompt_message"

module MCP
  class PromptResult
    include JSON::Serializable

    private getter messages = [] of PromptMessage

    protected def initialize; end

    delegate :<<, size, each, each_with_index, to: @messages

    def self.import(json : JSON::Any)
      prompt = self.new
      json.as_a.each do |msg_json|
        prompt << PromptMessage.import(msg_json)
      end
      prompt
    rescue ex
      STDERR.puts ex.inspect_with_backtrace
      raise ex
    end
  end
end
