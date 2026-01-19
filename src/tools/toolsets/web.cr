require "../toolset"
require "./web/*"

module Tools
  module Web
    MAX_CONTENT_SIZE = 256*1024

    TEXT_CTYPE_PREFIXES = [
      "text/",
    ]
    TEXT_CTYPE_SUFFIXES = [
      "/json",
      "/xml",
      "/yaml",
      "/toml",
    ]

    def self.text?(content_type)
      TEXT_CTYPE_PREFIXES.any? { |prefix| content_type.starts_with?(prefix) } ||
        TEXT_CTYPE_SUFFIXES.any? { |suffix| content_type.ends_with?(suffix) }
    end

    # setup the toolset
    toolset = ToolSet.create("Web") do
      hold HttpGetWebPageTool
      hold HttpGetWebAsMarkdownTool
    end
    Tools.register(toolset)
  end
end
