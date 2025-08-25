# The command parser is used to parse a command with parameters as follows:
# - All arguments are separated by spaces
# - Command can start with non-named arguments (positional) separated by spaces
# - First named argument means no more positional args
# - Names args are always K=V without spaces
# - Arguments can be quotes within '' or ""
# - No interpolation of values (for now?)
class CommandParser
  # Azure gpt-4o helped me with this. Wow.
  # Helps extract terms separated by spaces while preserving quotes
  private TERMRX = /(?:[^\s"']+|"[^"]*"|'[^']*')+/

  @pos_args = [] of String
  @named_args = {} of String => String
  @bad_args = [] of String

  # Portions of command we couldn't parse, or nil if none
  getter missed : String?

  def initialize(query)
    # Split by space, preserve quotes
    remainder = query.gsub(TERMRX) do |term|
      parts = term.split('=', 2)
      if parts.size > 1 && parts.first.match(/^[_a-zA-Z][_a-zA-Z0-9]+$/)
        @named_args[parts.first] = parts.last
      else
        # otherwise this is a positional, either OK or bad
        where = @named_args.empty? ? @pos_args : @bad_args
        where << disenquote(term)
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

  # Positional argument at index
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

  # Get the value of a named argument
  def arg_named?(name)
    @named_args[name.to_s]?
  end

  # Use this to see if the command matches expected arguments and parameters, where
  # values can be `String` (exact match), array of `String` (match one), or `Class` expressions (type match), and
  # also if extra args were found.
  # Example: `cmd.expect "/cmd", String, type: String?
  def expect?(*args, **params)
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
    # Check that parser didn't capture more args than expected
    return false unless checked_pos_count >= positional_count &&
                        checked_name_count >= named_count
    true # all matched
  end

  # Internal, to test if `arg_value` satisfies `value_spec`
  private def expect_test(value_spec, arg_value)
    case value_spec
    when String then value_spec == arg_value         # match exact
    when Array  then value_spec.includes?(arg_value) # match one of
    else
      value_spec === arg_value # match type
    end
  end

  private def disenquote(s)
    quoted?(s) ? s.lchop.rchop : s
  end

  private def quoted?(s)
    (s.starts_with?('\'') && s.ends_with?('\'')) ||
      (s.starts_with?('"') && s.ends_with?('"'))
  end
end
