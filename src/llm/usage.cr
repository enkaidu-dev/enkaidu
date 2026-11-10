require "json"

module LLM
  class Usage
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    getter prompt_tokens = 0
    getter completion_tokens = 0
    getter total_tokens = 0

    # Build a canonical `Usage` from a Responses-API usage object, whose fields
    # are `input_tokens`/`output_tokens` (mapped onto the canonical
    # `prompt_tokens`/`completion_tokens`); `total_tokens` is kept as-is.
    def self.from_responses(json : JSON::Any) : Usage
      h = json.as_h.dup
      if v = h["input_tokens"]?
        h["prompt_tokens"] = v
      else
        h["prompt_tokens"] = JSON::Any.new(0) unless h.has_key?("prompt_tokens")
      end
      if v = h["output_tokens"]?
        h["completion_tokens"] = v
      else
        h["completion_tokens"] = JSON::Any.new(0) unless h.has_key?("completion_tokens")
      end
      h.delete("input_tokens")
      h.delete("output_tokens")
      h["total_tokens"] = (h["total_tokens"]? || JSON::Any.new(0))
      Usage.from_json(h.to_json)
    end
  end
end
