require "yaml"
require "json"
require "json-schema"

module Enkaidu
  # Convenient serializable class that contains common functionality: automatic
  # interpolation of env vars in `String` values. Currently supports config properties
  # with values of type `String`, `String?`, `Hash(String,String)` and `Array(String)`
  class ConfigSerializable
    include YAML::Serializable
    include YAML::Serializable::Strict

    include JSON::Serializable

    private def gsub_with_env(value : String)
      #
      # Pretty nasty bunch of regex ... replace with something better
      # one day.
      #
      # check if it has ${XXX:default} in it and replace with environment var
      # of default value
      tmp = value.gsub(/\$*\$\{[A-Za-z_][A-Za-z0-9_]*:-.+\}/) do |var_w_def|
        if (ix = var_w_def.index('{')) && ix.odd?
          # odd no. of '$', so keep even number (or none if 1), and interpolate
          keep = ix > 1 ? var_w_def[..ix - 2] : ""
          var_w_def = var_w_def[(ix + 1)..].rchop('}')
          var, defval = var_w_def.split(":-", 2)
          keep + (ENV[var]? || defval)
        else
          var_w_def # don't interpolate, even # of '$'
        end
      end
      # check if it has $XXX in it and replace with environment var
      tmp = tmp.gsub(/\$*\$[A-za-z_][A-za-z0-9_]*/) do |var|
        # Find last $ in sequence of odd $'s
        if (ix = var.index(/\$[^\$]/)) && !ix.odd?
          # odd no. of '$', so keep even number (or none if 1), and interpolate
          keep = ix.zero? ? "" : var[..ix - 1]
          keep + (ENV[var[(ix + 1)..]]? || var)
        else
          var # don't interpolate, even # of '$'
        end
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

    # This convenience macro intentionally doesn't use `TypeDeclaration` macro-level type node
    # to work around an emaba bug: https://github.com/crystal-ameba/ameba/issues/447
    macro getter_with_presence(name, type)
      {% presence_name = "#{name}_present".id %}
      {% if @top_level.has_constant?("JSON") %}  @[JSON::Field(ignore: true)]   {% end %}
      {% if @top_level.has_constant?("YAML") %}  @[YAML::Field(ignore: true)]   {% end %}
      getter? {{presence_name}} : Bool

      # Now declare the getter for which we want to detect presence
      {% if @top_level.has_constant?("YAML") %}  @[YAML::Field(presence: true)]  {% end %}
      getter {{ name }} : {{ type }}
    end

    # Support env var substitution for all instance vars with
    # `String` values
    def after_initialize
      post_process_string_values
    end
  end
end
