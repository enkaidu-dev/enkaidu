require "html5"

class HtmlToMarkdown
  class ParseError < RuntimeError; end

  # List of HTML tags that are self-closing and don't require a closing tag
  IMPLICIT_SELF_CLOSING_TAGS = [
    "area", "base", "img", "input", "link", "meta", "br", "hr",
    "embed", "source", "track", "wbr",
  ]

  # List of HTML tags that are considered inline text elements
  INLINE_TEXT_TAGS = [
    "span", "a", "b", "i", "u", "em", "small", "big", "del",
    "ins", "sub", "sup", "code", "input", "label",
  ]

  # List of HTML tags that should be ignored during conversion
  IGNORE_KNOWN_TAGS = [
    "span", "small", "link", "meta", "big", "header",
    "nav", "label", "input", "html", "body", "article",
    "main", "aside", "footer", "section", "cite",
    "noscript",
  ]

  private getter io : IO
  private getter tag_stack = [] of String
  private getter tokenizer : HTML5::Tokenizer

  # HTML-specific state we track to be able to
  # decorate Markdown appropriately and keep the Markdown
  # clean / spare.
  #
  private getter list_nesting = 0
  private getter anchor_href : String? = nil
  private getter? started_newline = false
  private getter? inside_pre = false

  def initialize(@io)
    @tokenizer = HTML5::Tokenizer.new io
  end

  # Renders text content to Markdown, handling whitespace and formatting appropriately.
  # The rendering behavior changes based on context (e.g., inside <pre> tags, inline elements).
  private def render_text(markdown : IO, content : String)
    # This is messy because HTML can have lots of whitespace
    # between tags that is ignored, and which can lead to
    # big gaps in generated Markdown without using some state to
    # know when to strip text, when to skip newlines, etc.
    if inside_pre?
      # Within <pre> a lot of syntax highlighting libs embed spans
      # and styles ... but in the end, no trimming should be done.
      markdown << content
      @started_newline = content.ends_with?('\n')
    elsif (enclosing_tag = tag_stack.last?) && INLINE_TEXT_TAGS.includes?(enclosing_tag)
      # Within inline tags ...
      text = content.strip
      unless text.empty?
        markdown << text
        @started_newline = false
      end
    else
      # Otherwise ...
      text = content.lstrip
      unless text.empty?
        rtext = text.rstrip
        markdown << ' ' if text.size < content.size && !started_newline?
        markdown << rtext
        if text.rindex('\n').nil?
          markdown << ' ' if rtext.size < text.size
          @started_newline = false
        else
          markdown << '\n'
          @started_newline = true
        end
      end
    end
  end

  # Retrieves the value of an attribute from a list of HTML attributes.
  private def get_attr?(attributes : Array(HTML5::Attribute), name : String) : String?
    attributes.each do |attr|
      return attr.val if attr.key == name
    end
    # else nil
  end

  # Determines the prefix for list items based on the most recent list type in the tag stack.
  private def list_item_prefix : String
    tag_stack.reverse_each do |tag|
      return "* " if tag == "ul"
      return "1. " if tag == "ol"
    end
    ""
  end

  # Renders the start of an HTML tag, converting it to appropriate Markdown syntax.
  # ameba:disable Metrics/CyclomaticComplexity: For now I want to see it all in one switch
  private def render_start_tag(markdown : IO, name : String, attributes : Array(HTML5::Attribute), self_closing = false)
    case name
    when "pre"
      markdown << "\n```\n"
      @inside_pre = true
    when "code"        then markdown << "`" unless inside_pre?
    when "b", "strong" then markdown << "**"
    when "i", "em"     then markdown << "_"
    when "del"         then markdown << "~~"
    when "ins", "u"    then markdown << "++"
    when "sup"         then markdown << "^"
    when "sub"         then markdown << "~"
    when "br"
      markdown << '\n' unless started_newline?
      markdown << '\n'
      @started_newline = true
    when "hr"
      markdown << "\n---\n"
      @started_newline = true
    when /h[1-6]/
      markdown << '\n'
      case name
      when "h1" then markdown << "# "
      when "h2" then markdown << "## "
      when "h3" then markdown << "### "
      when "h4" then markdown << "#### "
      when "h5" then markdown << "##### "
      when "h6" then markdown << "###### "
      end
      @list_nesting = 0
    when "div"
      unless get_attr?(attributes, "class")
        unless started_newline?
          markdown << "\n\n"
          @started_newline = true
        end
      end
    when "p"
      unless started_newline?
        markdown << "\n\n"
        @started_newline = true
      end
    when "a"
      if href = get_attr?(attributes, "href")
        @anchor_href = href
      end
      markdown << '['
    when "img"
      if src = get_attr?(attributes, "src")
        if alt = get_attr?(attributes, "alt")
          markdown << "![" << alt << ']'
        else
          markdown << "![]"
        end
        markdown << '(' << src << ')'
      end
    when "head", "script", "style", "form", "button", "svg"
      skip_until(name)
    when "table", "thead", "tbody", "th", "tr", "td"
      # keep the tags in the Markdown
      markdown << '\n' if !started_newline? && name == "table"
      markdown << '<' << name << '>'
      @started_newline = false
    when "li"
      markdown << '\n' unless started_newline?
      (list_nesting - 1).times do
        markdown << "    "
      end
      markdown << list_item_prefix
    when "ol", "ul"
      unless started_newline?
        markdown << "\n\n"
        @started_newline = true
      end
      @list_nesting += 1
    else
      unless IGNORE_KNOWN_TAGS.includes?(name)
        STDERR.puts "Unable to render; ignoring start tag: <#{name} ...>"
      end
    end
  end

  # Renders the end of an HTML tag, closing Markdown syntax appropriately.
  # ameba:disable Metrics/CyclomaticComplexity: For now I want to see it all in one switch
  private def render_end_tag(markdown : IO, name : String)
    case name
    when "pre"
      markdown << '\n' unless started_newline?
      markdown << "```\n"
      @inside_pre = false
    when "code"        then markdown << "`" unless inside_pre?
    when "b", "strong" then markdown << "**"
    when "i", "em"     then markdown << "_"
    when "del"         then markdown << "~~"
    when "ins", "u"    then markdown << "++"
    when "sup"         then markdown << "^"
    when "sub"         then markdown << "~"
    when "h1", "h2", "h3", "h4", "h5", "h6", "div", "li", "p"
      unless started_newline?
        markdown << '\n'
        @started_newline = true
      end
      markdown << '\n' if name.starts_with?('h')
    when "a"
      markdown << "](" << anchor_href << ") "
      @anchor_href = nil
    when "ol", "ul"
      unless started_newline?
        markdown << "\n"
        @started_newline = true
      end
      @list_nesting = Math.max(0, list_nesting - 1)
    when "table", "thead", "tbody", "th", "tr", "td"
      # keep the tags in the Markdown
      markdown << "</" << name << '>'
      if @started_newline = (name == "table")
        markdown << '\n'
      end
    else
      unless IGNORE_KNOWN_TAGS.includes?(name)
        STDERR.puts "Unable to render; ignoring end tag: </#{name}>"
      end
    end
  end

  # Skips HTML content until a matching closing tag is found.
  # Used to ignore tags like <head>, <script>, and <style>.
  # ameba:disable Metrics/CyclomaticComplexity: Not worth splitting this up.
  private def skip_until(closing_tag : String)
    save_tag_stack = tag_stack
    @tag_stack = [] of String
    while tok_type = tokenizer.next
      break if tok_type.error? && tokenizer.eof?
      token = tokenizer.token
      case token.type
      when .error?
        raise ParseError.new("#skip_until: Error tokenizing HTML")
      when .start_tag?
        name = token.data
        self_closing = IMPLICIT_SELF_CLOSING_TAGS.includes?(name)
        tag_stack.push name unless self_closing
      when .end_tag?
        name = token.data
        break if name == closing_tag && tag_stack.empty?

        if peek = tag_stack.last
          if peek == name
            tag_stack.pop
          else
            STDERR.puts("#skip_until: Expected \"#{peek}\", but found: #{name}")
          end
        end
      end
    end
    @tag_stack = save_tag_stack
    tag_stack.pop unless tokenizer.eof?
  end

  # Checks if an end tag is acceptable in the current context.
  private def acceptable_end_tag?(end_tag, parent_tag)
    # HTML is weird, so allow in addition to when they match:
    # - <li> without matching </li> when list ends
    # - <p> without matching </p>
    (end_tag == parent_tag) ||
      (parent_tag == "li" && ["ol", "ul", "div"].includes?(end_tag)) ||
      (parent_tag == "p")
  end

  # Unwinds the tag stack to ensure proper closing of nested tags.
  private def unwind_tag_stack(markdown : IO, end_tag : String)
    while (parent = tag_stack.last) && parent != end_tag
      # unwind stack until we find expected parent
      tag_stack.pop
      render_end_tag(markdown, parent)
    end
  end

  # Processes a single HTML token and converts it to Markdown.
  # ameba:disable Metrics/CyclomaticComplexity: Not worth splitting this up.
  private def process_token(markdown : IO, token : HTML5::Token)
    case token.type
    when .error?
      raise ParseError.new("Error tokenizing HTML")
    when .text?
      render_text(markdown, token.data)
    when .start_tag?
      name = token.data
      self_closing = IMPLICIT_SELF_CLOSING_TAGS.includes?(name)
      tag_stack.push name unless self_closing
      render_start_tag(markdown, name, token.attr, self_closing)
    when .end_tag?
      name = token.data
      if parent = tag_stack.last
        if acceptable_end_tag?(name, parent)
          unwind_tag_stack(markdown, end_tag: name)
          tag_stack.pop
          render_end_tag(markdown, name)
        else
          STDERR.puts("Unexpected end tag. Expected </#{parent}>, but found: </#{name}>")
        end
      end
    when .self_closing_tag?
      name = token.data
      render_start_tag(markdown, name, token.attr, self_closing: true)
    when .doctype?
      name = token.data
      STDERR.puts("Unexpected DOCTYPE: #{name}") if name.downcase != "html"
    when .comment?
      # skip
    end
  end

  # Converts the entire HTML input to Markdown format.
  protected def convert : String
    String.build do |markdown|
      while tok_type = tokenizer.next
        break if tok_type.error? && tokenizer.eof?

        token = tokenizer.token
        process_token(markdown, token)
      end
    end
  end

  # Static method to convert HTML from an IO source to Markdown.
  def self.translate(io : IO) : String
    self.new(io).convert
  end
end
