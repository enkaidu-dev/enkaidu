require "../config"

module Enkaidu
  class InvalidMacroCall < Exception; end

  # Defines the kinds of sub-macro blocks within a macro
  # definition.
  enum MacroBlockCommand
    Enter # sequential queries

    def self.parse?(name) : self?
      case name
      when "<enter>" then Enter
      end
    end

    def self.parse(name) : self
      parse?(name) || ArgumentError.new("Invalid name for enum: #{name}")
    end
  end

  class RawMacro < ConfigSerializable
    # Generate the finite-depth sequence of nested statements
    # where lowest level Stmt0 is String | Hash(String, String)
    # and levels above are String | Hash(String, <Prev level's Stmt?>)
    macro define_recursive_stmt_type(new_type_name, depth)
      {%
        # use new type name as the prefix
        sub_type_prefix = new_type_name
      %}

      # :nodoc:
      alias {{ (sub_type_prefix.stringify + 0.stringify).id }} =
        String | Hash(String, Array(String))

      {% for i in (0...depth) %}
            {% p = i %}
            {% q = i + 1 %}
        # :nodoc:
        alias {{ (sub_type_prefix.stringify + q.stringify).id }} =
          String | Hash(String, Array({{ (sub_type_prefix.stringify + p.stringify).id }}))
      {% end %}

        # :nodoc:
      alias {{ new_type_name }} = {{ (sub_type_prefix.stringify + depth.stringify).id }}
    end

    define_recursive_stmt_type(Stmt, 3)

    alias Block = Array(Stmt)

    getter description : String
    getter queries : Block

    # Return false if blocks are invalid.
    def valid?
      valid_stmt?(queries)
    end

    private def valid_stmt?(block)
      block.all? do |query|
        case query
        when String then true
        when Hash
          query.each.all? do |cmd, nested_block|
            # Blocks must have supported block command names
            MacroBlockCommand.parse?(cmd.strip.split(limit: 2).first) &&
              valid_stmt?(nested_block)
          end
        end
      end
    end
  end

  class PreparedMacro
    # Keep the way the macro was called, or sub-macro was entered
    getter invocation : String
    # Queries include sub-macro blocks
    getter queries : Array(String | PreparedMacro)

    def initialize(@invocation, @queries); end
  end

  class MacroProcessingHelper
    private getter options : SessionOptions

    private def profile
      options.profile
    end

    private def config
      options.config
    end

    private def renderer
      options.renderer
    end

    def initialize(@options); end

    # Locate a macro by name, prioritizing config macros with the same name over
    # profile ones.
    def find_macro_by_name?(name) : Config::Macro?
      ((macros = config.macros) && macros[name]?) || profile.macros[name]?
    end

    # Traverse macros, prioritizing config macros with the same name over
    # profile ones.
    def each_macro(&)
      if config_macros = config.macros
        config_macros.each do |name, mac|
          yield name, mac, "Config"
        end
        profile.macros.each do |name, mac|
          # Macro with same name in config file supercedes profile
          yield name, mac, "Profile" unless config_macros[name]?
        end
      else
        profile.macros.each do |name, mac|
          yield name, mac, "Profile"
        end
      end
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

    private def prepare_nested_macro(cmd, invocation, mac_queries)
      prepared_queries = [] of String | PreparedMacro
      prepared_invocation = substitute_macro_call_args(invocation, cmd)
      # substitute args
      mac_queries.each do |query|
        case query
        when String
          prepared_queries << substitute_macro_call_args(query, cmd)
        when Hash
          query.each do |key, value|
            prepared_queries << prepare_nested_macro(cmd, key, value)
          end
        end
      end
      PreparedMacro.new(prepared_invocation, prepared_queries)
    end

    # Invoking a macro supports positional and named parameter substitution. For a found macro,
    # each query is prepared for use by looking for `%{number}` or `%{word}` patterns, where
    # `number` patterns are replaced with positional arguments (0 is the macro name) and
    # `word` patterns are replaced with named arguments. If any are not found, the macro call is
    # aborted and a warning with the missing parameter is issued.
    def find_and_prepare_macro(macro_call) : PreparedMacro?
      if macro_call.starts_with? '!'
        cmd = CommandParser.new(macro_call)
        mac_name = cmd.arg_at(0)[1..]
        if mac = find_macro_by_name?(mac_name)
          # prepared_queries = [] of String | PreparedMacro
          # # substitute args
          # mac.queries.each do |query|
          #   prepared_queries << substitute_macro_call_args(query, cmd)
          # end
          # PreparedMacro.new(macro_call, prepared_queries)
          prepare_nested_macro(cmd, macro_call, mac.queries)
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
