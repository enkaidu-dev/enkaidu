require "./param_type"

module LLM
  # The `Param` class defines the schema for a single parameter
  class Param
    getter name : String
    getter type : ParamType
    getter description : String
    getter? required

    def initialize(@name, @type, @description, @required = false)
    end
  end
end
