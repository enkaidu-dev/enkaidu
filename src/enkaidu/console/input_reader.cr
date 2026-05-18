require "reply"
require "colorize"

module Enkaidu::Console
  class InputReader < Reply::Reader
    property label : String
    private getter styler : Console::StyleApplicator

    DELIMETERS = {{" \n\t'\"=".chars}}

    def initialize(@label, @styler)
      super()
      editor.word_delimiters = DELIMETERS
    end

    def prompt(io : IO, line_number : Int32, color : Bool) : Nil
      q = label.colorize(:cyan) if color
      io << q
    end

    # Override to integrate auto-completion.
    #
    # *current_word* is picked following `word_delimiters`.
    # It expects to return `Tuple` with:
    # * a title : `String`
    # * the auto-completion results : `Array(String)`
    #
    # default: `{"", [] of String}`
    def auto_complete(current_word : String, expression_before : String)
      if current_word.starts_with?("./")
        # Tab completion for paths in current folder
        if current_word.size > 2 && Path::SEPARATORS.includes?(current_word[-1])
          current_word = current_word[0..-2]
        end
        path = Path.new(current_word)
        path = path.parent unless File.directory?(path)
        {
          "Files and Folders",
          Dir.new(path).children.map { |name| (path / name).to_s },
        }
      else
        # Nothing to complete
        {"", [] of String}
      end
    end

    # Highlight the expression
    def highlight(expression : String) : String
      # Paths that start with `./`
      expression.gsub(/\.(\/[^\s]+)+\/?/) do |match|
        styler.fmt(:query_syntax_path, match)
      end
    end
  end
end
