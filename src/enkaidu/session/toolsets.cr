require "../../tools"

module Enkaidu
  class Session
    module Toolsets
      def list_all_tools
        text = String.build do |io|
          chat.each_tool_origin do |origin|
            io << "### " << origin << '\n'
            chat.each_tool(origin: origin) do |tool|
              io << "`" << tool.name << "` : "
              io << tool.description << "\n\n"
            end
          end
          io << '\n'
        end
        renderer.respond_with("List of available tools.", text, markdown: true)
      end

      def unload_all_toolsets
        @loaded_toolsets.keys.each do |name|
          unload_toolset_by(name)
        end
      end

      def unload_toolset_by(name, auto = false)
        toolset = Tools[name]?
        if toolset.nil?
          renderer.warning_with("WARNING: No built-in toolset found under the name: #{name}.")
        elsif !@loaded_toolsets.has_key?(name)
          renderer.info_with("INFO: Built-in toolset not loaded: #{name}.")
        else
          message = String.build do |str|
            str << "Unloaded built-in tools from toolset: "
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
          if auto
            renderer.info_with message
          else
            renderer.respond_with message
          end
        end
      end

      def tool_loaded?(name : String)
        chat.find_tool?(name)
      end

      private def load_tool_by_class(tool_class) : LLM::Function
        fun_name = tool_class.function_name
        settings = opts.config.tool_settings_by_name(fun_name)
        tool = tool_class.new(renderer, settings)
        chat.with_tool(tool)
        tool
      end

      def load_toolset_by(name, select_tools : Enumerable(String)? = nil, auto = false) : Nil
        toolset = Tools[name]?
        if toolset.nil?
          renderer.warning_with("WARNING: No built-in toolset found under the name: #{name}.")
        else
          # Load selected tools or all tools in toolset
          selection = select_tools || toolset.tool_names # select all tool names
          # Filter out tool names in selection that are alreadyloaded
          selection = selection.select { |tool_name| !chat.find_tool?(tool_name) }
          if selection && selection.empty?
            renderer.info_with "INFO: Built-in tools in toolset already loaded."
          else
            message = String.build do |str|
              str << "Loaded built-in tools from toolset: "
              ix = 0
              toolset.retrieve(selection: selection) do |built_in_function_class|
                tool = load_tool_by_class(built_in_function_class)
                str << ", " if ix.positive?
                str << tool.name
                ix += 1
              end
            end
            if auto
              renderer.info_with message
            else
              renderer.respond_with message
            end
          end
          @loaded_toolsets[name] = toolset
        end
      end

      # This is for use by the tool for installing tools, and it searches across
      # all toolsets.
      def load_tools_across_toolsets(tool_names : Enumerable(String))
        loaded = [] of NamedTuple(toolset: String, tool: String)
        Tools.each_toolset do |toolset|
          toolset.each_tool_class do |name, tool_class|
            next unless tool_names.includes?(name)
            unless tool_loaded?(name)
              load_tool_by_class(tool_class)
            end
            loaded << {toolset: toolset.name, tool: name}
          end
        end
        loaded # return list of tools loaded.
      end

      def list_all_toolsets
        text = String.build do |io|
          Tools.each_toolset do |toolset|
            loaded = @loaded_toolsets.has_key?(toolset.name)
            io << "# " << toolset.name
            io << (loaded ? " _(Loaded)_\n" : '\n')
            toolset.each_tool_info do |name, description|
              io << "* `" << name << "` : "
              io << description << "\n\n"
            end
          end
          io << '\n'
        end
        renderer.respond_with("List of available toolsets.", text, markdown: true)
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
          renderer.respond_with("Tool details: #{tool_name} (#{tool.origin})", text, markdown: true)
        else
          renderer.info_with("INFO: No such tool available: #{tool_name}")
        end
      end

      # Adds an array of tools to the JSON builder. Call it when ready for an array
      # value.
      def tools_catalog_builder(json : JSON::Builder) : Nil
        json.array do
          Tools.each_toolset do |toolset|
            toolset.each_tool_info do |name, description|
              json.object do
                json.field "tool", name
                json.field "toolset", toolset.name
                json.field "description", description
              end
            end
          end
        end
      end
    end
  end
end
