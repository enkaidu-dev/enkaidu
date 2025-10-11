require "../../tools"

module Enkaidu
  class Session
    module Toolsets
      def list_all_tools
        text = String.build do |io|
          chat.each_tool_origin do |origin|
            io << "## " << origin << '\n'
            chat.each_tool(origin: origin) do |tool|
              io << "**" << tool.name << "** : "
              io << tool.description << "\n\n"
            end
          end
          io << '\n'
        end
        renderer.info_with("List of available tools.", text, markdown: true)
      end

      def unload_all_toolsets
        @loaded_toolsets.keys.each do |name|
          unload_toolset_by(name)
        end
      end

      def unload_toolset_by(name)
        toolset = Tools[name]?
        if toolset.nil?
          renderer.warning_with("WARNING: No built-in toolset found under the name: #{name}.")
        elsif !@loaded_toolsets.has_key?(name)
          renderer.info_with("INFO: Built-in toolset not loaded: #{name}.")
        else
          message = String.build do |str|
            str << "INFO: Unloaded built-in tools from toolset: "
            ix = 0
            toolset.each_tool_info do |tool_name, _|
              next unless chat.find_tool? tool_name
              str << ", " if ix.positive?
              chat.without_tool(tool_name)
              str << tool_name
              ix += 1
            end
          end
          @loaded_toolsets.delete(name)
          renderer.info_with(message)
        end
      end

      def load_toolset_by(name, select_tools : Enumerable(String)? = nil)
        toolset = Tools[name]?
        if toolset.nil?
          renderer.warning_with("WARNING: No built-in toolset found under the name: #{name}.")
        else
          # Load selected tools or all tools in toolset
          selection = select_tools || toolset.tool_names # select all tool names
          # Filter out tool names in selection that are alreadyloaded
          selection = selection.select { |tool_name| !chat.find_tool?(tool_name) }
          message = if selection && selection.empty?
                      "INFO: Built-in tools in toolset already loaded."
                    else
                      String.build do |str|
                        str << "INFO: Loaded built-in tools from toolset: "
                        ix = 0
                        toolset.produce(renderer, selection: selection) do |tool|
                          str << ", " if ix.positive?
                          chat.with_tool(tool)
                          str << tool.name
                          ix += 1
                        end
                      end
                    end
          @loaded_toolsets[name] = toolset
          renderer.info_with(message)
        end
      end

      def list_all_toolsets
        text = String.build do |io|
          Tools.each_toolset do |toolset|
            loaded = @loaded_toolsets.has_key?(toolset.name)
            io << "### " << toolset.name
            io << (loaded ? " _(Loaded)_\n" : '\n')
            toolset.each_tool_info do |name, description|
              io << "* **" << name << "** : "
              io << description << "\n\n"
            end
          end
          io << '\n'
        end
        renderer.info_with("List of available toolsets.", text, markdown: true)
      end

      def list_tool_details(tool_name)
        if tool = chat.find_tool?(tool_name)
          text = String.build do |io|
            desc = if tool.description == tool_name
                     "_No description provided. Using tool name instead._"
                   else
                     tool.description
                   end
            io << desc << '\n'
            io << "### Input Schema (Parameters)\n```json\n"
            io << JSON.parse(tool.input_json_schema).to_pretty_json
            io << "\n```\n"
          end
          renderer.info_with("Tool details: #{tool_name} (#{tool.origin})", text, markdown: true)
        else
          renderer.info_with("INFO: No such tool available: #{tool_name}")
        end
      end
    end
  end
end
