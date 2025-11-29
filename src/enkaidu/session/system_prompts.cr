module Enkaidu
  class Session
    module SystemPrompts
      private def register_system_prompt_by_name(name, sys_prompt)
        system_prompts[name] = sys_prompt
      end

      def list_all_system_prompts
        text = String.build do |io|
          system_prompts.each_value do |sys_prompt|
            io << "**" << sys_prompt.name << "** (" << sys_prompt.origin << "): "
            io << sys_prompt.description << "\n\n"
          end
          io << '\n'
        end
        renderer.info_with("List of available system prompts.", text, markdown: true)
      end

      def find_system_prompt?(prompt_name)
        system_prompts[prompt_name]?
      end

      def render_system_prompt(prompt_name)
        if sys_prompt = find_system_prompt?(prompt_name)
          renderer.info_with("INFO: System prompt: #{sys_prompt.description}")
          sys_prompt.render(profile: opts.profile)
        else
          renderer.warning_with("WARN: Unable to find system prompt named: #{prompt_name}")
          nil
        end
      end
    end
  end
end
