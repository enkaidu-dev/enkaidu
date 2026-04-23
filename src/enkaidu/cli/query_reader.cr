require "reply"

require "../slash_commander"

module Enkaidu::CLI
  # Command-line query reader with editing and other capabilities.
  class QueryReader < Reply::Reader
    private getter runtime : Runtime

    DELIMETERS = {{" \n\t".chars}}

    def initialize(@runtime, @input_history_file : String? = nil)
      super()
      editor.word_delimiters = DELIMETERS
    end

    property prefix = "QUERY"

    def prompt(io : IO, line_number : Int32, color : Bool) : Nil
      q = "#{prefix} > "
      q = q.colorize(:yellow) if color
      io << q
    end

    # Cache command and macro docs to avoid re-endering markdown
    # over and over and over again
    @doc_cache = {} of String => String

    # Macro, because we don't want the doc generator to
    # execute before we check the cache
    macro cached_doc(name, doc_generator)
      if doc = @doc_cache[{{name}}]?
        doc
      elsif help = {{doc_generator}}
        @doc_cache[{{name}}] = Markd.to_term(help)
      end
    end

    # Override to set the entire documentation for an autocompletion entry.
    #
    # If not nil, the documentation is shown in its own alternate screen when alt-d is pressed.
    #
    # default: `nil`
    def documentation(entry : String)
      if entry.starts_with?('/')
        cached_doc(entry, runtime.commander.help_for(entry))
      elsif entry.starts_with?('!')
        cached_doc(entry, runtime.session.macro_description(entry))
      end
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
          Dir.new(path).children.map { |name| "#{path}/#{name}" },
        }
      elsif expression_before == ""
        # Tab completion for commands and macros
        {
          "Commands and Macros",
          [runtime.commander.command_names, runtime.session.macro_names].flatten,
        }
      else
        # Nothing to complete
        {"", [] of String}
      end
    end

    # def highlight(expression : String) : String
    #   # Highlight the expression
    # end

    # def continue?(expression : String) : Bool
    #   # Return whether the interface should continue on multiline, depending of the expression
    # end

    # def format(expression : String) : String?
    #   # Reformat when expression is submitted
    # end

    # def indentation_level(expression_before_cursor : String) : Int32?
    #   # Compute the indentation from the expression
    # end

    def save_in_history?(expression : String) : Bool
      true
    end

    def history_file
      @input_history_file ||= ENV.fetch("ENKAIDU_HISTORY_FILE", ".enkaidu_history")
    end

    # def auto_complete(name_filter : String, expression : String) : {String, Array(String)}
    #   # Return the auto-completion result from expression
    # end
  end
end
