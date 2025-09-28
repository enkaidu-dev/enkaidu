require "../event_renderer"

module Enkaidu::WUI::Render
  abstract class Event
    include JSON::Serializable

    use_json_discriminator "type", {
      message:            Message,
      query:              Query,
      llm_text:           LLMText,
      llm_text_fragment:  LLMTextFragment,
      llm_tool_call:      LLMToolCall,
      shell_confirmation: ShellConfirmation,
      session_update:     SessionUpdate,
    }

    getter type : String
    getter time = Time.local

    def initialize(@type); end
  end
end
