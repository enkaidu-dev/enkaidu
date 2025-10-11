require "../../tools"

module Enkaidu
  class Session
    module AutoLoad
      # Run auto loads specified in the session config
      def auto_load
        return unless config = opts.config

        if auto_load = config.session.try &.auto_load
          if mcp_servers = config.mcp_servers
            if (mcp_server_names = auto_load.mcp_servers) && mcp_server_names.present?
              renderer.info_with("INFO: Auto-loading MCP servers: #{mcp_server_names.join(", ")}")
              auto_load_mcp_servers(mcp_servers, mcp_server_names)
            end
          end

          if (toolsets = auto_load.toolsets) && toolsets.present?
            renderer.info_with("INFO: Auto-loading toolsets: #{toolsets.join(", ")}")
            auto_load_toolsets(toolsets)
          end
        end

        if prompts = config.prompts
          renderer.info_with("INFO: Auto-loading prompts: #{prompts.keys.join(", ")}")
          auto_load_config_prompts(prompts)
        end
      end

      private def auto_load_config_prompts(prompts)
        prompts.each do |name, prompt|
          tp = TemplatePrompt.new(name, prompt, self)
          template_prompts << tp
          register_prompt_by_name(name, tp)
        end
      end

      private def auto_load_mcp_servers(mcp_servers, mcp_server_names)
        mcp_server_names.each do |mcp_name|
          mcp_name = mcp_name.strip

          use_mcp_by(mcp_name)
        end
      end

      private def auto_load_toolsets(toolsets)
        toolsets.each do |toolset|
          if toolset.is_a? String
            load_toolset_by(toolset.strip)
          elsif toolset.is_a? NamedTuple
            load_toolset_by(toolset[:name].strip, toolset[:select])
          end
        end
      end
    end
  end
end
