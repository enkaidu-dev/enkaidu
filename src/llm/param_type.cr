module LLM
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
