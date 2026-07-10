require "../../sucre/command_parser"
require "../../sucre/key_value_store"
require "../../tools"

module Enkaidu
  class ConditionalCommandHelper
    include Tools::FileHelper

    NAME = "?break"

    HELP_BRIEF = "`#{NAME} <sub-command> ...` - Conditionally exit from current macro"
    HELP       = <<-HELP1
    #{HELP_BRIEF}
    - `if file_exists=<PATH>`
      - Exit macro if given file exists
    - `if file=<PATH> contains=<STR>`
      - Exit macro if given file exists and contains given string
    - `if global ns=<NAMESPACE> key=<STR> equals=<STR>`
      - Exit macro if global state key has matching value
    - `unless file_exists=<PATH>`
      - Exit macro unless given file exists
    - `unless file=<PATH> contains=<STR>`
      - Exit macro unless given file exists and contains given string
    - `unless global ns=<NAMESPACE> key=<STR> equals=<STR>`
      - Exit macro unless global state key has matching value
    HELP1

    # Detailed help, in Markdown
    def help : String
      HELP
    end

    # One line help, in Markdown
    def brief : String
      HELP_BRIEF
    end

    def name : String
      NAME
    end

    # Defines the next step following a conditional command
    enum Continue
      # Yes means continue with next command in queue
      Yes
      # Break means discard current "frame" queue, and continue with next "frame" in the stack
      # Effectively terminates current macro
      Break
      # Abort means discard current frame queue and all queues in the stack, returning user to
      # the prompt. Reserved for errors
      Abort
    end

    # Conditional command handling returns a continuation response
    # with a `Continue` value and an optional message.
    alias Continuation = NamedTuple(continue: Continue, message: String?)

    # Return a Tuple with
    # - continuation with Abort and message if error, OR
    # - resolved file path
    private def resolve_and_validate(file : String) : Continuation | String
      resolved = resolve_path(file)

      unless within_current_directory?(resolved)
        return {continue: Continue::Abort, message: "ERROR: File is outside current folder, not allowed."}
      end

      resolved
    end

    # Return a continuation after checking if  given file exists.
    private def break_if_file_exists(file : String) : Continuation
      case result = resolve_and_validate(file)
      when Continuation then result
      else
        resolved_file = result
        continue = Continue::Yes
        message = nil.as(String?)
        if file_exists?(resolved_file)
          continue = Continue::Break
          message = "INFO: Break: File exists: #{file}"
        end
        {continue: continue, message: message}
      end
    end

    # Return a continuation after checking if given file does not exists.
    private def break_unless_file_exists(file : String) : Continuation
      case result = resolve_and_validate(file)
      when Continuation then result
      else
        resolved_file = result
        continue = Continue::Yes
        message = nil.as(String?)
        unless File.exists?(resolved_file)
          continue = Continue::Break
          message = "INFO: Break: File does not exist: #{file}"
        end
        {continue: continue, message: message}
      end
    end

    # Return a continuation if given `file` exists AND `contains` the given string.
    private def break_if_file_contains(file : String, contains : String) : Continuation
      case result = resolve_and_validate(file)
      when Continuation then result
      else
        resolved_file = result
        continue = Continue::Yes
        if File.exists?(resolved_file) && File.read(resolved_file).includes?(contains)
          continue = Continue::Break
          message = "INFO: Break: File contains \"#{contains}\""
        end
        {continue: continue, message: message}
      end
    end

    # Return a continuation unless given `file` exists AND `contains` the given string.
    private def break_unless_file_contains(file : String, contains : String) : Continuation
      case result = resolve_and_validate(file)
      when Continuation then result
      else
        resolved_file = result
        continue = Continue::Break
        if File.exists?(resolved_file) && File.read(resolved_file).includes?(contains)
          continue = Continue::Yes
        else
          message = "INFO: Break: File doesn't exist, or doesn't contain \"#{contains}\""
        end
        {continue: continue, message: message}
      end
    end

    # Return a continuation if given `key` in `namespace` of global state has a matching `value`.
    private def break_if_global_state_equals(global_state : KeyValueStore::InMemory,
                                             ns : String,
                                             key : String,
                                             equals : String) : Continuation
      continue = Continue::Yes
      message = nil
      if (value = global_state.get?(ns, key)) && value == equals
        continue = Continue::Break
        message = "INFO: Break: Global state key's value equals: #{equals}"
      end
      {continue: continue, message: message}
    end

    # Return a continuation unless given `key` in `namespace` of global state has a matching `value`.
    private def break_unless_global_state_equals(global_state : KeyValueStore::InMemory,
                                                 ns : String,
                                                 key : String,
                                                 equals : String) : Continuation
      continue = Continue::Break
      message = nil
      if (value = global_state.get?(ns, key)) && value == equals
        continue = Continue::Yes
      else
        message = "INFO: Break: Global state key doesn't exist, or value doesn't equal: #{equals}"
      end
      {continue: continue, message: message}
    end

    # Return true to continue with next query, or
    # false to abort current query queue
    def handle_conditional_command(session_manager : SessionManager, q : String) : Continuation
      case cmd = CommandParser.new(q)
      when .expect?("?break", "if", file_exists: String)
        break_if_file_exists(
          file: cmd.arg_named("file_exists").as(String))
      when .expect?("?break", "if", file: String, contains: String)
        break_if_file_contains(
          file: cmd.arg_named("file").as(String),
          contains: cmd.arg_named("contains").as(String))
      when .expect?("?break", "if", "global", ns: String, key: String, equals: String)
        break_if_global_state_equals(
          session_manager.global_state,
          ns: cmd.arg_named("ns").as(String),
          key: cmd.arg_named("key").as(String),
          equals: cmd.arg_named("equals").as(String))
      when .expect?("?break", "unless", file_exists: String)
        break_unless_file_exists(
          file: cmd.arg_named("file_exists").as(String))
      when .expect?("?break", "unless", file: String, contains: String)
        break_unless_file_contains(
          file: cmd.arg_named("file").as(String),
          contains: cmd.arg_named("contains").as(String))
      when .expect?("?break", "unless", "global", ns: String, key: String, equals: String)
        break_unless_global_state_equals(
          session_manager.global_state,
          ns: cmd.arg_named("ns").as(String),
          key: cmd.arg_named("key").as(String),
          equals: cmd.arg_named("equals").as(String))
      else
        {
          continue: Continue::Abort,
          message:  "ERROR: Aborting! Unknown conditional command: #{q}",
        }
      end
    end
  end
end
