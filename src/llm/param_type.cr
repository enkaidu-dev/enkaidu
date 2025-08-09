module LLM
  # The `ParamType` defines an enumeration of supported types for
  # tool calling parameters
  enum ParamType
    Obj
    Bool
    Num
    Arr
    Str

    def label
      case self
      in .obj?  then "object"
      in .bool? then "boolean"
      in .num?  then "number"
      in .arr?  then "array"
      in .str?  then "string"
      end
    end
  end
end
