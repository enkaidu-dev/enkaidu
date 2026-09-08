module Enkaidu
  class Session
    module SystemPrompts
      private def register_system_prompt_by_name(name, sys_prompt)
        system_prompts[name] = sys_prompt
      end

      def list_all_system_prompts
        text = String.build do |io|
          system_prompts.each do |key, sys_prompt|
            io << "(" << key << ") "
            io << "`" << sys_prompt.name << "` (" << sys_prompt.origin << "): "
            io << sys_prompt.description << "\n\n"
          end
          io << '\n'
        end
        renderer.respond_with("List of available system prompts.", text, markdown: true)
      end

      def find_system_prompt?(prompt_name)
        system_prompts[prompt_name]?
      end

      private def render_system_prompt(prompt_name)
        if sys_prompt = find_system_prompt?(prompt_name)
          renderer.info_with("System prompt: #{sys_prompt.description}")
          sys_prompt.render(profile: opts.profile)
        else
          renderer.warning_with("Unable to find system prompt named: #{prompt_name}")
          nil
        end
      end

      def reset_system_prompt(system_prompt_name : String)
        if sys_prompt = render_system_prompt(system_prompt_name)
          @chat.with_system_message(system_prompt(sys_prompt))
        end
      end
    end
  end
end
