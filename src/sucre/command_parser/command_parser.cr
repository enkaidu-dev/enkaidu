# The command parser is used to parse a command with parameters as follows:
# - All arguments are separated by spaces
# - Command can start with non-named arguments (positional) separated by spaces
# - First named argument means no more positional args
# - Names args are always K=V without spaces
# - Arguments can be quoted within '' or ""
# - Arguments can be arrays of values, within square brackets and separated by spaces.
# - No interpolation of values (for now?)
class CommandParser
  # Helps extract terms separated by spaces while preserving quotes
  private VALUE_TERM_RX = /(?:[^\s"']+|"[^"]*"|'[^']*')+/

  # Additionally detects variable assignments where VAR=VALUE where VALUE can be quoted
  # Additional detect arrays of values grouped by square brackets
  private TERM_PARSE_RX = /(?:[a-zA-Z_][0-9a-zA-Z_]*=(?:[^\s"'\[]+|"[^"]*"|'[^']*'|\[(?:[^\[\]"']|"[^"]*"|'[^']*')*\])|\[(?:[^\[\]"']|"[^"]*"|'[^']*')*\]|"[^"]*"|'[^']*'|[^\s"']+)+/

  private VARNAME_RX = /^[_a-zA-Z][_a-zA-Z0-9]*$/

  getter input : String

  @pos_args = [] of String | Array(String)
  @named_args = {} of String => String | Array(String)
  @bad_args = [] of String | Array(String)

  # Portions of command we couldn't parse, or nil if none
  getter missed : String?

  # Value can be string, quoted string, array of values
  private def parse_value(str)
    if str.match(/\[[^\[]*\]/)
      str = str.lchop.rchop.strip
      arr = [] of String
      str.scan(VALUE_TERM_RX) do |match|
        arr << disenquote(match.to_s)
      end
      arr
    else
      disenquote(str)
    end
  end

  def initialize(query)
    @input = query.clone
    # Split by space, preserve quotes
    remainder = query.gsub(TERM_PARSE_RX) do |term|
      parts = term.split('=', 2)
      if parts.size > 1 && parts.first.match(VARNAME_RX)
        @named_args[parts.first] = parse_value(parts.last)
      else
        # otherwise this is a positional, either OK or bad
        where = @named_args.empty? ? @pos_args : @bad_args
        where << parse_value(term)
      end
      "" # replace with blanks
    end
    remainder = remainder.strip # remainder should only be spaces; so ...
    @missed = remainder.blank? ? nil : remainder
  end

  # Number of positional arguments (up to the first named argument, if any)
  def positional_count
    @pos_args.size
  end

  # Positional argument at index, raising exception if no such index
  def arg_at(index)
    @pos_args[index.to_i]
  end

  # Positional argument at index, return `nil` if no such index
  def arg_at?(index)
    @pos_args[index.to_i]?
  end

  # Number of positional args that occurred after the first named argument was found
  def bad_count
    @bad_args.size
  end

  # Iterate thru the bad positional arguments
  def each_bad(&)
    @bad_args.each { |term| yield term }
  end

  # Number of named arguments
  def named_count
    @named_args.size
  end

  # Get the value of a named argument, raising exception if no such named argument
  def arg_named(name)
    @named_args[name.to_s]
  end

  # Get the value of a named argument, return specified default value or `nil` if no such named argument
  def arg_named?(name, default = nil)
    @named_args[name.to_s]? || default
  end

  # private TRACE = 1

  # Use this to see if the command matches expected arguments and parameters, where
  # values can be `String` (exact match), array of `String` (match one), `Class` expressions (type match), or
  # any other "subsumption operator" matches (i.e. `===`) include Regex expression.
  # Example: `cmd.expect "/cmd", String, type: String?
  def expect?(*args, **params)
    {% if @type.has_constant?("TRACE") %}
    {% if flag?(:test) %}
      STDERR.puts
    {% end %}
    STDERR.puts "#expect? args: #{args}".colorize(:yellow)
    STDERR.puts "         params: #{params}".colorize(:yellow)
    STDERR.puts "         missed: #{missed}".colorize(:yellow)
    {% end %}
    # If we have junk no point in checking anything else
    return false if missed
    # Check the positional args
    checked_pos_count = 0
    args.each_with_index do |arg_spec, i|
      checked_pos_count += 1
      next if expect_test(arg_spec, arg_at?(i))
      return false # mismatch
    end
    # Checked the named args
    checked_name_count = 0
    params.each do |name, value_spec|
      checked_name_count += 1
      next if expect_test(value_spec, arg_named? name)
      return false # mismatch
    end
    {% if @type.has_constant?("TRACE") %}
      STDERR.puts "#expect? checked_pos_count: #{checked_pos_count} >= positional_count: #{positional_count}, checked_name_count: #{checked_name_count} >= named_count: #{named_count}".colorize(:yellow)
    {% end %}
    # Check that parser didn't capture more args than expected
    return false unless checked_pos_count >= positional_count &&
                        checked_name_count >= named_count
    true # all matched
  end

  # Internal, to test if `arg_value` satisfies `value_spec`
  private def expect_test(value_spec, arg_value)
    {% if @type.has_constant?("TRACE") %}
      STDERR.puts "#expect_test value_spec: #{value_spec.class}, arg_value: #{arg_value.try(&.class) || "<nil>"}"
    {% end %}
    result = case value_spec
             when String then value_spec == arg_value # match exact
             when Array
               case arg_value
               when Array
                 value_spec.includes?(arg_value) || value_spec == arg_value
               else
                 value_spec.includes?(arg_value) # match one of
               end
             else
               value_spec === arg_value # match type
             end
    {% if @type.has_constant?("TRACE") %}
      STDERR.puts "#expect_test value_spec: #{value_spec}, arg_value: #{arg_value || "<nil>"} => #{result}"
    {% end %}
    result
  end

  private def disenquote(s)
    quoted?(s) ? s.lchop.rchop : s
  end

  private def quoted?(s)
    (s.starts_with?('\'') && s.ends_with?('\'')) ||
      (s.starts_with?('"') && s.ends_with?('"'))
  end
end
