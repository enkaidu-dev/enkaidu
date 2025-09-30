require "./function"

module LLM
  # Defines a subclass of Function that can be used to
  # implement local (in-code) tools / functions easily
  abstract class LocalFunction < Function
    # The `Param` class defines the schema for a single parameter of a `LocalFunction`
    class Param
      # The `Param::Type` defines an enumeration of supported types for
      # tool calling parameters
      enum Type
        Obj
        Bool
        Num
        Arr
        Str

        def json_type
          case self
          in .obj?  then "object"
          in .bool? then "boolean"
          in .num?  then "number"
          in .arr?  then "array"
          in .str?  then "string"
          end
        end
      end

      getter name : String
      getter type : Type
      getter description : String
      getter? required

      def initialize(@name, @type, @description, @required = false)
      end
    end

    # one list per class; do not edit
    @@params = [] of Param
    @@input_schema = nil

    def initialize(origin = "LEGACY / Built-in")
      super(origin)
    end

    # Iterate through each parameter
    private def each_param(& : Param ->)
      @@params.each do |param|
        yield param
      end
    end

    # The input schema for the parameters to this function, into the JSON builder.
    def input_json_schema(json : JSON::Builder)
      @@input_schema ||= json.object do
        required = [] of String
        json.field "type", "object"
        json.field "properties" do
          json.object do
            each_param do |param|
              json.field param.name do
                json.object do
                  json.field "type", param.type.json_type
                  json.field "description", param.description
                end
              end
              required << param.name if param.required?
            end
          end
        end
        unless required.empty?
          json.field "required" do
            json.array do
              required.each do |req|
                json.string req
              end
            end
          end
        end
      end
    end

    # Set the name for the function.
    macro name(str)
      # The name of the function
      def self.function_name : String
        {{str}}
      end

      # The name of the function
      def name : String
        {{str}}
      end
    end

    # Set the description for the function.
    macro description(str)
      # The description of the function.
      def self.description : String
        {{str}}
      end

      # The description of the function.
      def description : String
        {{str}}
      end
    end

    # Define a parameter for this LLM Function.
    macro param(name, description, type = Param::Type::Str, required = false)
      @@params << Param.new({{name}}, {{type}}, {{description}}, {{required}})
    end

    # Define the method that is used to create the Runner
    macro runner(runner_type)
      # Return an instance of this function's Runner
      def new_runner : Runner
        {{runner_type}}.new
      end
    end
  end
end
