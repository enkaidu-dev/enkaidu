# Command Parser 

The `CommandParser` is designed to handle command-line input parsing. It is suitable for applications that require command parsing with both positional and named arguments with single and multiple values (lists).

## Features

- **Positional Arguments**: 
  - The command can start with positional arguments which are separated by spaces.
  - The presence of the first named argument terminates the sequence of positional arguments. 
  - Any positional arguments following a named one are considered "bad" positional arguments and available for inspection separately.

- **Named Arguments**:
  - Named arguments are specified with the syntax `key=value`.
  - No spaces are allowed between the key, equals sign, and value.
 
- **Quoting**:
  - Arguments can be enclosed with either single (`'`) or double (`"") quotes to preserve spaces within them.
  
- **Arrays**:
  - Arguments can be arrays of strings specified using square brackets `[]` and separated by spaces
  - Arrays can contain quoted and unquoted values.
  
- **No Interpolation**: 
  - The current implementation does not support interpolation within the arguments.

- **Input Handling**:
  - Unrecognized or malformed portions of the input can be accessed through the `missed` property.

## Example Command Structure

A typical command using this parser might look like:

```
command positional1 [positional2a pos2b]  key1=value1 key2=[value2 value3] key3="quoted value"
```

- `positional1` and `[positional2a pos2b]` are positional arguments.
- `key1=value1` is a named argument with a single value.
- `key2=[value2 value3]` is a named argument with an array of values.
- `key3="quoted value"` is a named argument where the value contains spaces.

## Usage

To utilize the `CommandParser`, create an instance with the command string as input:

```crystal
parser = CommandParser.new("your command string")
```

From there, you can interact with the parser to access its positional and named arguments, detect errors, and more.

## Expectation Matching

The `expect?` method is used to verify if the parsed command meets specific criteria for arguments.

### Syntax

```crystal
parser.expect?(positional_matchers, **named_matchers)
```

- **Positional Matchers**: Define expected values for positional arguments by their order. 
- **Named Matchers**: A hash where keys are argument names and values are the expected criteria, similar to positional matchers.

### Value matching 

Matching is done as follows:

- _Exact matching_: when the value matcher is the same type as the argument value.
- _RegEx matching_: when the value matcher is a `Regex` value, for use with single `String` values only
- _Includes matching_: when the value matcher is an array of the same type as the argument value.
- _Type matching_: when matchers are `Class` and union types, to check if argument values fit the type

### Example

```crystal
command_string = "copy source.txt target.txt mode=overwrite verbose=[true false]"
parser = CommandParser.new(command_string)

if parser.expect?("copy", String, mode: "overwrite", verbose: Array)
  puts "Command is valid and matches expectations!"
else
  puts "Command does not meet expected format."
end
```

In this example:
- The first positional argument must be `"copy"`.
- The second and third should be of `String` type.
- The named argument `mode` requires an exact match of `"overwrite"`.
- The `verbose` named argument must be an array.

This method returns `true` if all criteria are met without extraneous arguments; otherwise, it returns `false`.
