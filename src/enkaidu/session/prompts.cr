module Enkaidu
  class Session
    module Prompts
      private def register_prompt_by_name(name, prompt)
        prompts_by_name[name] = prompt
      end

      def list_all_prompts
        text = String.build do |io|
          prompts_by_name.each_value do |prompt|
            # mcp_prompts.each do |prompt|
            io << "**" << prompt.name << "** (" << prompt.origin << "): "
            io << prompt.description << "\n\n"
          end
          io << '\n'
        end
        renderer.info_with("List of available prompts.", text, markdown: true)
      end

      def list_prompt_details(prompt_name)
        if sel_prompt = find_prompt?(prompt_name)
          text = String.build do |io|
            desc = if sel_prompt.description == prompt_name
                     "_No description provided. Using tool name instead._"
                   else
                     sel_prompt.description
                   end
            io << desc << '\n' << '\n'
            if args = sel_prompt.arguments
              io << "### Arguments" << '\n'
              args.each do |arg|
                io << "* `" << arg.name << "`: " << (arg.description || "_(No description)_") << '\n'
              end
              io << '\n'
            end
          end
          renderer.info_with("Prompt details: #{prompt_name} (#{sel_prompt.origin})", text, markdown: true)
        else
          renderer.info_with("INFO: No such prompt available: #{prompt_name}")
        end
      end

      def find_prompt?(prompt_name)
        prompts_by_name[prompt_name]?
      end

      def use_prompt(prompt_name)
        if prompt = find_prompt?(prompt_name)
          case prompt
          when MCPPrompt
            arg_inputs = renderer.mcp_prompt_ask_input(prompt)
            unless (prompt_result = prompt.call_with(arg_inputs)).nil?
              text_count = 0
              chat.import(prompt_result, emit: true) do |chat_ev|
                text_count = render_session_event chat_ev, text_count
              end
              ask(query: nil, attach: nil)
            end
          when TemplatePrompt
            arg_inputs = renderer.user_prompt_ask_input(prompt)
            prompt_text = prompt.call_with(arg_inputs)
            ask(query: prompt_text, render_query: true)
          end
        end
      rescue ex
        handle_mcpc_error(ex)
      end

      private def unload_all_prompts
        template_prompts.clear
        prompts_by_name.clear
      end
    end
  end
end
