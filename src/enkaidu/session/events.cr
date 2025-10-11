module Enkaidu
  class Session
    module Events
      private def render_session_event(chat_ev, text_count)
        case chat_ev["type"]
        when "text"
          renderer.llm_text_block(chat_ev["content"].as_s)
          text_count += 1
        when "tool_call"
          text_count = 0
          renderer.llm_tool_call(
            name: chat_ev["content"].dig("function", "name").as_s,
            args: chat_ev["content"].dig("function", "arguments"))
        when "tool_called"
        when "query/text"
          renderer.user_query_text(chat_ev["content"].as_s)
          text_count += 1
        when "query/image_url"
          renderer.user_query_image_url(chat_ev["content"].as_s)
        when "query/file_data"
          renderer.info_with("INCLUDE file: #{chat_ev["content"].as_s}")
        end
        text_count
      end

      private def tail_session_events(num_chats)
        text_count = 0
        @chat.tail_session(num_chats) do |chat_ev|
          text_count = render_session_event chat_ev, text_count
        end
      end

      private def process_event(r, tools)
        case r["type"]
        when "tool_call"
          tools << r["content"]
          renderer.llm_tool_call(
            name: r["content"].dig("function", "name").as_s,
            args: r["content"].dig("function", "arguments"))
        when "text"
          renderer.llm_text(r["content"].as_s)
        when .starts_with? "error"
          renderer.llm_error(r["content"])
        end
      end
    end
  end
end
