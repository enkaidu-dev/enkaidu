require "json"

module LLM
  class Error < Exception; end

  class ServerError < Error
    getter data : JSON::Any?

    def initialize(message : String? = nil, @data : JSON::Any? = nil)
      super(message || @data.try(&.to_json))
    end

    def initialize(@data : JSON::Any)
      super(@data.to_json)
    end
  end

  class UnexpectedResponseError < Error
    getter data : JSON::Any?

    def initialize(message : String? = nil, @data : JSON::Any? = nil)
      super(message || @data.try(&.to_json))
    end

    def initialize(@data : JSON::Any)
      super(@data.to_json)
    end
  end

  # Canonical event names emitted by protocol decoders and consumed by the app
  # layer. Per P4 the app only ever sees these canonical names; protocol-specific
  # wire event names never leak across the module boundary.
  enum Event
    DebugRequest
    DebugData
    Text
    ReasoningEvent
    ReceivingToolCall
    ToolCallRequested
    ToolCallMerge
    CallingTool
    ToolCallDone
    FinishReason
    QueryAudio
    QueryFileData
    QueryImageUrl
    QueryText
    Usage
    Done
    WarnTooManyRequestsDelay
    WarnUnexpected
    WarnUnknownToolCall

    def debug_event?
      self == DebugRequest || self == DebugData
    end

    def warn_event?
      self == WarnTooManyRequestsDelay || self == WarnUnexpected || self == WarnUnknownToolCall
    end
  end

  # Canonical chat event — the protocol-neutral tuple the app layer consumes.
  # Kept as a leaf (only `Event` + JSON) so `history`, `message`, `content`,
  # and the protocol adapters can depend on it without a back-edge into `Chat`.
  alias ChatEvent = NamedTuple(type: Event, content: JSON::Any)
end
