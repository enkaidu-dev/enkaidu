require "./llm"
require "./enkaidu/session_renderer"
require "./tools/*"

# Local tools live under the `Tools` module in sub-modules which can
# register as tool-sets
module Tools
  @@registry = {} of String => ToolSet

  def self.register(toolset : ToolSet)
    return if @@registry.has_key?(toolset.name)

    @@registry[toolset.name] = toolset
  end

  # Call Tools[name]? to find a ToolSet by its name
  def self.[]?(name) : ToolSet?
    @@registry[name]?
  end

  # Call Tools.each_toolset to iterate through known ToolSet's
  def self.each_toolset(& : ToolSet ->)
    @@registry.each_value do |toolset|
      yield toolset
    end
  end

  # Call Tools.each_toolset to iterate through known ToolSet's
  def self.each_toolset
    @@registry.each_value
  end
end
