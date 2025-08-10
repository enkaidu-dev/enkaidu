module LLM
  class ParamTypeException < Exception; end

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

    def self.from(label) : ParamType
      case label
      when "object"  then ParamType::Obj
      when "boolean" then ParamType::Bool
      when "number"  then ParamType::Num
      when "array"   then ParamType::Arr
      when "string"  then ParamType::Str
      else
        raise ParamTypeException.new("Unknown parameter type label: #{label}")
      end
    end
  end
end
