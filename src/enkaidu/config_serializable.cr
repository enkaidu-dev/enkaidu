require "yaml"

module Enkaidu
  # Convenient serializable class that contains common functionality: automatic
  # interpolation of env vars in `String` values. Currently supports config properties
  # with values of type `String`, `String?`, `Hash(String,String)` and `Array(String)`
  class ConfigSerializable
    include YAML::Serializable

    private def gsub_with_env(value : String)
      # check if it has $XXX in it and replace with environment var
      tmp = value.gsub(/\$[A-za-z-_]+/) do |var|
        # look up without $ prefix
        ENV[var.lchop('$')]
      end
      tmp
    end

    # Use within `#after_initialize method to map interpolate env vars in
    # vars of following types: `String`, `String?`, `Hash(String,String)`, `Array(String)`
    macro post_process_string_values
      {% for var in @type.instance_vars %}
      {% if typ = var.type %}
        {% if typ == String %}
          @{{ var.name }} = gsub_with_env( {{ var.name }})
        {% elsif typ == String? %}
          if tmp = {{ var.name }}
            @{{ var.name }} = gsub_with_env(tmp)
          end
        {% elsif typ == Hash(String, String) %}
          tmp_{{var}} = {{typ}}.new
          {{var}}.each do |name, value|
            tmp_{{var}}[name] = gsub_with_env(value)
          end
          @{{var}} = tmp_{{var}}
        {% elsif typ == Array(String) %}
          tmp_{{var}} = [] of String
          {{var}}.each do |value|
            tmp_{{var}} << gsub_with_env(value)
          end
          @{{var}} = tmp_{{var}}
        {% end %}
      {% end %}
      {% end %}
    end

    # Support env var substitution for all instance vars with
    # `String` values
    def after_initialize
      post_process_string_values
    end
  end
end
