require "./env/*"

module Enkaidu::Env
  private macro define_sys_props
    {% target_triple = Crystal::TARGET_TRIPLE.split('-') %}
    SYSTEM_PROPERTIES = Variables{
      "os_arch" => {{ target_triple.first }},
      "os_name" => {{ target_triple.last }},
    }
  end

  # Hash of system properties
  define_sys_props
end
