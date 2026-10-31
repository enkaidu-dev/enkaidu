require "http"
require "json"
require "io/memory"

# Shared scaffolding for the LLM specs.
#
# The specs target a locally-running Ollama (its OpenAI-compatible
# endpoint at localhost:11434) so no cloud credentials or usage credits
# are needed. HTTP traffic is intercepted by wiretap: the first run
# records a transcript under `spec/transcripts/`, and every later run
# replays it offline and deterministically.
#
# Include `LLMSpecHelpers` in a spec to use the helpers below. Reference
# the shared constants via `LLMSpecHelpers::MODEL` etc. (Crystal resolves
# constants lexically, so the module-qualified form is used in specs).

module LLMSpecHelpers
  # The model the specs use. Kept in one place so it's trivial to change.
  MODEL = "ornith-1.5:9b"

  # The local Ollama OpenAI-compatible endpoint.
  OLLAMA_ENDPOINT = "http://localhost:11434"

  # Transcript and prompt shared by the history round-trip specs, so they can
  # reuse the already-recorded non-streaming ask instead of making live calls.
  NON_STREAMING_ASK_TRANSCRIPT = "ollama_ask_non_streaming"
  POPULATE_PROMPT              = "Say hello, world. Reply in one short sentence."

  # Run a block with the Ollama provider's environment forced so the specs
  # are deterministic regardless of the host's real environment.
  def with_ollama_envs(&)
    ENV["OLLAMA_ENDPOINT"] = OLLAMA_ENDPOINT
    ENV["OLLAMA_API_KEY"]  = "ollama"
    yield
  ensure
    ENV.delete("OLLAMA_ENDPOINT")
    ENV.delete("OLLAMA_API_KEY")
  end

  # Build a fresh Ollama-backed `LLM::Chat` with the shared model set, and
  # return it so the caller can drive it (`ask`, `re_ask`, ...).
  def build_ollama_chat(model_name : String = LLMSpecHelpers::MODEL) : LLM::Chat
    with_ollama_envs do
      connection = LLM::Ollama::Connection.new
      connection.new_chat do
        with_model model_name
      end
    end
  end

  # Collect the `ChatEvent`s yielded by `chat.ask(prompt)`.
  def ask_events(chat : LLM::Chat, prompt : String) : Array(LLM::ChatEvent)
    events = [] of LLM::ChatEvent
    chat.ask(prompt) { |ev| events << ev }
    events
  end

  # Collect the `ChatEvent`s yielded by `chat.re_ask`.
  def re_ask_events(chat : LLM::Chat) : Array(LLM::ChatEvent)
    events = [] of LLM::ChatEvent
    chat.re_ask { |ev| events << ev }
    events
  end

  # Concatenate the `text` events' contents into the full reply text.
  def reply_text(events) : String
    events.select { |e| e["type"] == "text" }.map { |e| e["content"].as_s }.join
  end

  # The JSON request body of the first interaction in a recorded transcript.
  def recorded_request_body(transcript_name : String) : JSON::Any
    transcript = Wiretap::Transcript.load_or_create(transcript_name, :once)
    JSON.parse(transcript.interactions.first.request.body.not_nil!)
  end

  # Serialize a chat's history to a JSON string via the `save` path.
  def save_chat_json(chat : LLM::Chat) : String
    mem = IO::Memory.new
    chat.save(mem)
    mem.rewind
    mem.gets_to_end
  end

  # Load a chat's history from a JSON string via the `load` path.
  def restore_chat(chat : LLM::Chat, json : String) : Nil
    chat.load(json)
  end

  # The JSON of a chat's last full conversation, for comparing round-trips.
  def last_conversation_json(chat : LLM::Chat) : String
    chat.extract_conversations(LLM::Conversation::LatestFull).not_nil!
  end

  # Build an Ollama chat and populate its history by *replaying* the recorded
  # non-streaming ask transcript (no live network). The returned chat's history
  # then holds a user prompt plus an assistant response, which the history specs
  # use to exercise fork / save / load without issuing any new requests.
  def populated_ollama_chat : LLM::Chat
    chat = build_ollama_chat
    Wiretap.intercept(NON_STREAMING_ASK_TRANSCRIPT) do
      ask_events(chat, POPULATE_PROMPT)
    end
    chat
  end
end

# A minimal read-only tool for the LLM tool-call specs. The model is prompted
# to call it; its runner echoes the `value` argument back verbatim.
class TestEchoTool < LLM::LocalFunction
  name "echo"
  description "Echoes the given value back verbatim. You MUST call this tool whenever the user asks you to echo or repeat a value."
  param "value", "The value to echo back.", required: true
  side_effects LLM::Function::SideEffects::FileRead
  runner TestEchoTool::Runner

  class Runner < LLM::Function::Runner
    def execute(args : JSON::Any) : String
      {echoed: args["value"].as_s}.to_json
    end
  end
end
