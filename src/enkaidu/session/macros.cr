module Enkaidu
  class Session
    module Macros
      # Locate a macro by name, prioritizing config macros with the same name over
      # profile ones.
      def find_macro_by_name?(name) : Config::Macro?
        ((macros = opts.config.macros) && macros[name]?) || opts.profile.macros[name]?
      end

      # Traverse macros, prioritizing config macros with the same name over
      # profile ones.
      private def each_macro(&)
        if config_macros = opts.config.macros
          config_macros.each do |name, mac|
            yield name, mac, "Config"
          end
          opts.profile.macros.each do |name, mac|
            # Macro with same name in config file supercedes profile
            yield name, mac, "Profile" unless config_macros[name]?
          end
        else
          opts.profile.macros.each do |name, mac|
            yield name, mac, "Profile"
          end
        end
      end

      @macro_cache = [] of String

      def macro_names : Array(String)
        if @macro_cache.size.zero?
          each_macro do |name, _mac, _origin|
            @macro_cache << "!#{name}"
          end
          @macro_cache.sort!
        end
        @macro_cache
      end

      def macro_description(name) : String?
        if mac = (find_macro_by_name?(name) || find_macro_by_name?(name = name[1..-1]))
          "`!#{name}` - #{mac.description}"
        end
      end

      def list_all_macros
        text = String.build do |io|
          each_macro do |name, mac, origin|
            io.puts "----"
            io << "`" << name << "` (_" << origin << "_) - "
            io << mac.description << "\n\n"
          end
          io << '\n'
        end
        renderer.respond_with("List of available macros.", text, markdown: true)
      end

      private def substitute_macro_call_args(line : String, cmd : CommandParser)
        # check if `line` has %{X} in it and replace with argument,
        # using %{<N>} for positional or %{<KEY>} for named
        tmp = line.gsub /(%+)\{([A-za-z0-9_]+)\}/ do |var, matches|
          if matches[1].size.odd?
            # odd no. of '%', so keep even number (or none if 1), and interpolate
            keep = matches[1][1..]
            key = matches[2]
            if key =~ /\d+/
              if val = cmd.arg_at?(key)
                keep + val.to_s
              else
                raise InvalidMacroCall.new("WARN: Missing positional arg %{#{key}} in macro call")
              end
            else
              if val = cmd.arg_named?(key)
                keep + val.to_s
              else
                raise InvalidMacroCall.new("WARN: Missing named arg %{#{key}} in macro call")
              end
            end
          else
            var # don't interpolate
          end
        end
        tmp
      end

      # Invoking a macro supports positional and named parameter substitution. For a found macro,
      # each query is prepared for use by looking for `%{number}` or `%{word}` patterns, where
      # `number` patterns are replaced with positional arguments (0 is the macro name) and
      # `word` patterns are replaced with named arguments. If any are not found, the macro call is
      # aborted and a warning with the missing parameter is issued.
      def find_and_prepare_macro(macro_call)
        if macro_call.starts_with? '!'
          cmd = CommandParser.new(macro_call)
          prepared_queries = [] of String
          mac_name = cmd.arg_at(0)[1..]
          if mac = find_macro_by_name?(mac_name)
            # substitute args
            mac.queries.each do |query|
              prepared_queries << substitute_macro_call_args(query, cmd)
            end
            prepared_queries
          else
            renderer.warning_with("WARN: Unable to find macro: #{macro_call}")
            nil
          end
        end
      rescue ex : InvalidMacroCall
        renderer.warning_with(ex.to_s)
        nil
      end
    end
  end
end
