module LLM
  # The wire protocols this module supports. Each provider declares exactly one
  # (its highest-fidelity backend protocol); a ChatCompletions backend is a
  # compatibility path only.
  enum ProtocolKind
    ChatCompletions
    Responses
  end
end
