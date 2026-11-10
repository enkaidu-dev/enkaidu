require "./function"
require "./events"
require "./response_schema"
require "./chat_inclusions"
require "./function_call"
require "./history"
require "./usage"
require "../sucre/mcp_types"

module LLM
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
    getter model : String? = nil
    getter system_message : String? = nil
    getter? debug = false
    getter? streaming = false
    getter? readonly = false
    getter reasoning = Reasoning::Default
    getter temperature : Float32? = nil
    getter session_id : String? = nil

    # Session state moved up from the protocol adapters so that session
    # management (save/load/fork/squish/tail/…/append) and the tool loop are
    # protocol-agnostic. `usage` is the most recent response's usage.
    private getter history : History
    getter usage : Usage? = nil

    def initialize
      @tools_by_name = {} of String => Function
      @tools_by_origin = {} of String => Hash(String, Function)
      @history = History.new
    end

    def with_debug
      @debug = true
    end

    def with_session_id(sid : String)
      @session_id = sid
    end

    def with_reasoning(effort : Reasoning)
      @reasoning = effort
    end

    def with_streaming
      @streaming = true
    end

    # Use null to rever to default and not send property
    def with_temperature(level : Float32?)
      unless level && level.positive? && level <= 2
        raise ArgumentError.new("Temperature (#{level}) must be > 0 and <= 2.0")
      end

      @temperature = level
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
    def erase_history : Nil
      @history = History.new
      @usage = nil
    end

    def import(prompt : MCP::PromptResult, emit = false, & : ChatEvent ->) : Nil
      @history.import(prompt, emit) { |event| yield event }
    end

    # Invoke tool calls and return number of calls made; if positive call `re_ask` to
    # hand call results to the models to process
    def call_tools_and_setup_ask(tool_calls : Array(FunctionCall), & : ChatEvent ->) : Int32
      attachments = nil.as(Message::MultiContent?)
      calls = 0
      tool_calls.each do |call|
        if tool = find_tool?(call.name)
          yield({type: Event::CallingTool, content: call.json})
          result = call_tool(tool, call, attachments)
          append_message(result[:tool_call_response])
          attachments = result[:attachments]
        else
          yield unknown_tool_call(call)
          append_message error_calling_tool(
            call.id,
            call.name,
            error: case call.name
            when .blank? then "The tool name cannot be empty string."
            else              "The tool #{call.name} is not installed. Consider installing it first."
            end
          )
        end
        calls += 1
      end
      unless attachments.nil?
        # Append the attachments after all the tool call responses
        append_message(attachments)
      end
      calls
    end

    private def call_tool(tool : Function,
                          tool_call : FunctionCall,
                          attachments : Message::MultiContent?)
      args = if tool_call.arguments.blank?
               JSON::Any.new(nil)
             else
               begin
                 JSON.parse(tool_call.arguments)
               rescue ex : JSON::ParseException
                 return {
                   tool_call_response: error_calling_tool(
                     tool_call.id,
                     tool.name,
                     error: "Invalid JSON arguments for tool #{tool.name}: #{ex.message}",
                     instruction: "Return with valid JSON arguments and retry the tool call."
                   ),
                   attachments: attachments,
                 }
               end
             end
      reply = tool.run(args)
      # Detect attachments and start gathering up to send after the tool call
      # responses. We need to do this to make sure we conform to the message ordering
      # enforced by many model servers.
      if reply.has_attachments?
        if attachments.nil?
          attachments = Message::MultiContent.new("Additional content related to prior tool calls.")
        end
        reply.each_attachment do |att|
          case att
          when Function::Reply::Text  then attachments.text(att.data)
          when Function::Reply::File  then attachments.file_data(att.base64_data, att.file_name)
          when Function::Reply::Image then attachments.image_url(att.image_url.to_s)
          when Function::Reply::Audio then attachments.input_audio(att.base64_data, att.format)
          end
        end
      end
      {
        tool_call_response: Message::ToolCall.new(tool_call_id: tool_call.id, name: tool.name, content: reply.content),
        attachments:        attachments,
      }
    end

    private def error_calling_tool(call_id, tool_name, error, instruction = nil.as(String?))
      Message::ToolCall.new(
        tool_call_id: call_id,
        name: tool_name,
        content: (instruction ? {error: error, instruction: instruction} : {error: error}).to_json)
    end

    private def unknown_tool_call(tool_call : FunctionCall)
      {type: Event::ErrorUnknownToolCall, content: tool_call.json}
    end

    # Resubmit current session as a query to get another answer
    def re_ask(response_schema : ResponseSchema? = nil,
               exclude_reasoning_in_history = false,
               exclude_reasoning_skip = 0,
               & : ChatEvent ->) : Nil
      post_session(response_schema, exclude_reasoning_in_history, exclude_reasoning_skip) do |msg|
        yield msg
      end
    end

    # Submit a query, with optional attachments and request for response as a JSON object by specifying a JSON schema.
    def ask(content : String,
            attach : ChatInclusions? = nil,
            response_schema : ResponseSchema? = nil,
            exclude_reasoning_in_history = false,
            exclude_reasoning_skip = 0,
            & : ChatEvent ->) : Nil
      append_message(Message::MultiContent.new(prompt: content, attach: attach))
      post_session(response_schema, exclude_reasoning_in_history, exclude_reasoning_skip) do |msg|
        yield msg
      end
    end

    def append_message(msg)
      usage = nil
      if msg.is_a? Message::Response
        @usage = usage = msg.usage
      end
      @history.append_message msg, usage
    end

    # Extract last response from `assistant` and yield it to caller to
    # process and return a named tuple with a `prompt` and `response` to return
    # as a message array that caller can inject into a session. Returns `false` if
    # no response in the current history.
    def append_last_response_as_prompt(to : Chat, prompt_prefix : String, new_response : String) : Bool
      @history.append_transformed_last_response?(to: to.@history) do |content|
        {
          response: new_response,
          prompt:   String.build { |str| str << prompt_prefix << content },
        }
      end
    end

    # Replace current session with a "fork" of the session from the given
    # `Chat` instance; may fail if `self` is not compatible.
    # Optionally, exclude the last "turn" (last user prompt and subsequent responses).
    def fork(from : Chat, exclude_last_turn = false) : Nil
      @history.branch(from.@history, exclude_last_turn)
      @usage = @history.last_usage
    end

    # Interrupt the session and roll back history to the start of the current/last turn,
    # dropping the user prompt and any partial assistant responses or tool calls.
    def interrupt_and_rollback : Bool
      @history.rollback_last_turn
    end

    # Interrupt the session and repair history for the current turn.
    # Synthesizes missing tool call responses for unfulfilled tool calls to satisfy model server protocol requirements,
    # and optionally appends a synthetic assistant response.
    def interrupt_and_cleanup(tool_cancel_message : String = "Execution cancelled by user.",
                              final_response : String? = nil) : Bool
      @history.cleanup_interrupted_turn(tool_cancel_message, final_response)
    end

    # Save chat history
    def save(io : IO | JSON::Builder) : Nil
      @history.to_json(io)
    end

    # Load chat history
    def load(io : IO | String) : Nil
      @history = History.from_json(io)
      @usage = @history.last_usage
    end

    # Squish the session by keeping the initial request and final response for
    # each turn, dropping everything in between.
    def squish
      @history = @history.squish_turns
      @usage = nil
    end

    # Yield the latest `num_responses` messages from chat history
    def tail(num_responses = 1, & : ChatEvent ->) : Nil
      @history.tail_chats(num_responses) { |chat_ev| yield chat_ev }
    end

    # Append latest `num_responses` messages to the target chat's history
    def send_tail(to : Chat, num_responses = 1, filter_by_role : String? = nil) : Nil
      @history.transfer_tail_chats(to: to.@history,
        num: num_responses, filter_by_role: filter_by_role)
    end

    # Append conversations to target chat's history
    def append_conversations(to : Chat, which : Conversation) : Bool
      case which
      when .latest_full?
        @history.append_last_conversation(to: to.@history)
      when .latest_outer?
        @history.append_last_conversation(to: to.@history, outer: true)
      when .session_full?
        @history.append_session_conversation(to: to.@history)
      when .session_outer?
        @history.append_session_conversation(to: to.@history, outer: true)
      end
      true
    end

    # Extract conversations and return as a JSON string or nil
    def extract_conversations(which : Conversation) : String?
      extract = case which
                when .latest_full?
                  @history.extract_last_conversation
                when .latest_outer?
                  @history.extract_last_conversation(outer: true)
                when .session_full?
                  @history.extract_session_conversation
                when .session_outer?
                  @history.extract_session_conversation(outer: true)
                end
      extract.try(&.to_json)
    end

    protected def warn_too_many_requests_delay(err : JSON::Any)
      {type: LLM::Event::WarnTooManyRequestsDelay, content: err}
    end

    # The one protocol contract: encode the current session, POST it, and yield
    # the canonical `ChatEvent`s (which the app consumes; the adapter appends the
    # resulting `Message::Response` with its `Usage` back to history).
    abstract def post_session(response_schema : ResponseSchema? = nil,
                              exclude_reasoning_in_history = false,
                              exclude_reasoning_skip = 0,
                              & : ChatEvent ->) : Nil
  end
end
