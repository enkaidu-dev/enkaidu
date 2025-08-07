require "./param_type"

module LLM
  class Param
    getter name : String
    getter type : ParamType
    getter description : String
    getter? required

    def initialize(@name, @type, @description, @required = false)
    end
  end
end
