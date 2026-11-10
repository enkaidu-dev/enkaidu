require "json"

module LLM
  # Canonical "the model asked to call this tool". Stable JSON shape:
  # {"id": ..., "name": ..., "arguments": "<json string>"}
  #
  # `arguments` is a JSON *string* (matches today's Chat Completions behavior);
  # decoders never re-encode it, only append (streaming). This is the single
  # boundary type between the app, the core, and the protocol adapters.
  class FunctionCall
    getter id : String
    getter name : String
    getter arguments : String

    def initialize(@id, @name, @arguments = ""); end

    # Canonical JSON object {id, name, arguments}.
    def json : JSON::Any
      JSON.parse({
        "id"        => id,
        "name"      => name,
        "arguments" => arguments,
      }.to_json)
    end

    def self.from_json(json : JSON::Any) : FunctionCall
      j = json.as_h
      FunctionCall.new(
        id: j.dig("id").as_s,
        name: j.dig("name").as_s,
        arguments: j.dig("arguments").as_s? || "",
      )
    end
  end
end
