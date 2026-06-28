require "./function"
require "./response_schema"
require "./chat_inclusions"
require "../sucre/mcp_types"

module LLM
  alias ChatEvent = NamedTuple(type: String, content: JSON::Any)

  enum Conversation
    LatestFull
    LatestOuter
    SessionFull
    SessionOuter
  end

  enum Reasoning
    None
    Low
    Medium
    High
    Max
    Default
  end

  class UnexpectedMCPPrompt < Exception; end

  # `Chat` is an abstract class that serves as a base for creating various chat implementations.
  abstract class Chat
    getter model : String | Nil = nil
    getter system_message : String | Nil = nil
    getter? debug = false
    getter? streaming = false
    getter? readonly = false
    getter reasoning = Reasoning::Default

    def initialize
      @tools_by_name = {} of String => Function
      @tools_by_origin = {} of String => Hash(String, Function)
    end

    def with_debug
      @debug = true
    end

    def with_reasoning(effort : Reasoning)
      @reasoning = effort
    end

    def with_streaming
      @streaming = true
    end

    # Make chat session read-only. This will remove all tools that are not readonly.
    def with_readonly
      @readonly = true

      # Find and remove any tools that are not read-only
      not_readonly = [] of Function
      each_tool do |tool|
        unless tool.side_effects.readonly?
          not_readonly << tool
        end
      end
      not_readonly.each do |tool|
        without_tool(tool)
      end
    end

    def with_model(model : String)
      @model = model
    end

    def with_system_message(content : String)
      @system_message = content
    end

    # Return nil if unable to use / enable the function
    def with_tool(function : Function) : Function?
      return if readonly? && !function.side_effects.readonly?
      return if @tools_by_name[function.name]?
      @tools_by_name[function.name] = function
      by_origin = @tools_by_origin[function.origin]? ||
                  (@tools_by_origin[function.origin] = {} of String => Function)
      by_origin[function.name] = function
    end

    def without_tool(function_name)
      return unless function = @tools_by_name[function_name]?

      if by_origin = @tools_by_origin[function.origin]?
        by_origin.delete(function_name)
      end
      @tools_by_name.delete(function_name)
    end

    def find_tool?(name)
      @tools_by_name[name]?
    end

    def each_tool_origin(&)
      @tools_by_origin.each { |name, by_origin| yield(name) unless by_origin.empty? }
    end

    def each_tool(origin : String? = nil, &)
      return unless tools = (origin ? @tools_by_origin[origin] : @tools_by_name)
      tools.each_value do |tool|
        yield tool
      end
    end

    def each_tool
      @tools_by_name.each_value
    end

    # Erase history but keep connection
    abstract def erase_history : Nil

    abstract def import(prompt : MCP::PromptResult, emit = false, & : ChatEvent ->) : Nil

    # Invoke tool calls and return number of calls made; if positive call `re_ask` to
    # hand call results to the models to process
    abstract def call_tools_and_setup_ask(tool_calls : Array(JSON::Any), & : LLM::ChatEvent ->) : Int32

    # Resubmit current session as a query to get another answer
    abstract def re_ask(response_schema : ResponseSchema? = nil, exclude_reasoning_in_history = false, & : ChatEvent ->) : Nil

    # Submit a query, with optional attachments and request for response as a JSON object by specifying a JSON schema.
    abstract def ask(content : String,
                     attach : ChatInclusions? = nil,
                     response_schema : ResponseSchema? = nil,
                     exclude_reasoning_in_history = false,
                     & : ChatEvent ->) : Nil

    # Replace current session with a "fork" of the session from the given
    # `Chat` instance; may fail if `self` is not compatible.
    abstract def fork(from : Chat) : Nil

    # Save chat history
    abstract def save(io : IO | JSON::Builder) : Nil

    # Load chat history
    abstract def load(io : IO | String) : Nil

    # Yield the latest `num_responses` messages from chat history
    abstract def tail(num_responses = 1, & : ChatEvent ->) : Nil

    # Append latest `num_responses` messages to the target chat's history
    abstract def send_tail(to : Chat, num_responses = 1, filter_by_role : String = nil) : Nil

    # Append conversations to target chat's history
    abstract def append_conversations(to : Chat, which : Conversation) : Bool

    # Extract conversations and return as a JSON string or nil
    abstract def extract_conversations(which : Conversation) : String?
  end
end
