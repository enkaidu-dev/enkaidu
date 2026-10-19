require "../event_renderer"

module Enkaidu::WUI::Render
  abstract class Event
    include JSON::Serializable

    use_json_discriminator "type", {
      message:               Message,
      query:                 Query,
      llm_text:              LLMText,
      llm_text_fragment:     LLMTextFragment,
      llm_tool_call:         LLMToolCall,
      llm_image_url:         LLMImageUrl,
      ask_for_inputs:        AskForInputs,
      security_confirmation: SecurityConfirmation,
      security_permission:   SecurityPermission,
      session_reset:         SessionReset,
      session_info:          SessionInfo,
      session_shutdown:      SessionShutdown,
      system_info:           SystemInfo,
      help_response:         HelpResponse,
    }

    getter type : String
    getter time = Time.local

    def initialize(@type); end
  end
end
