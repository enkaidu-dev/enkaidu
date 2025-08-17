require "json"
require "yaml"

# Comment out constant to enable YAML config file
USE_JSON = 1

module Enkaidu
  {% if @top_level.has_constant?("USE_JSON") %}
    alias ConfigSerializable = JSON::Serializable
    alias ConfigSerializableError = JSON::SerializableError
    DEFAULT_CONFIG_FILE = "./enkaidu.json"
  {% else %}
    alias ConfigSerializable = YAML::Serializable
    alias ConfigSerializableError = YAML::ParseException
    DEFAULT_CONFIG_FILE = "./enkaidu.yaml"
  {% end %}

  class Config
    include ConfigSerializable

    {% if @top_level.has_constant?("USE_JSON") %}
      FORMAT = "JSON"
    {% else %}
      FORMAT = "YAML"
    {% end %}

    def self.parse(text : String)
      {% if @top_level.has_constant?("USE_JSON") %}
        from_json(text)
      {% else %}
        from_yaml(text)
      {% end %}
    end

    class Model
      include ConfigSerializable

      getter name : String
      getter model : String
    end

    class LLM
      include ConfigSerializable

      getter provider : String
      getter endpoint : String
      getter models : Array(Model)?
    end

    class Options
      include ConfigSerializable

      getter provider : String?
      getter model : String?
      getter recording_file : String?
      getter? trace_mcp = false
      getter? streaming = false
      getter? enable_shell_command = true
    end

    getter default : Options?
    getter llms : Array(LLM)?

    # Returns a NamedTuple or nil
    def find_llm_by_model_name?(unique_model_name)
      llms.try &.each do |llm|
        llm.models.try &.each do |model|
          if model.name == unique_model_name
            return {
              provider: llm.provider,
              endpoint: llm.endpoint,
              model:    model.model,
            }
          end
        end
      end
    end
  end
end
