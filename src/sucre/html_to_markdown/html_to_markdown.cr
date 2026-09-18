require "html5"
require "uri"

# Converts HTML into compact Markdown, built for feeding page content to
# a language model rather than for faithful visual rendering.
#
# ```
# File.open(path, "w") do |file|
#   result = FsUtils::Web::HtmlToMarkdown.translate(source, file, base_url: "https://example.com/docs/x")
#   result.bytes      # -> 41_233
#   result.truncated? # -> false
# end
# ```
#
# Writes Markdown to `output` and reports how much, so a caller can
# decide between inlining the content and handing back a file path
# without a second pass over it.
#
# `base_url` resolves relative `href` and `src` values. Same-origin
# results come back root-relative, which costs a caller the obligation to
# prepend the origin when following a link and saves tens of thousands of
# tokens on a page that links within itself.
#
# `max_bytes` stops the walk once that much Markdown has been written and
# reports `truncated`. It bounds the *output*; the input is the fetcher's
# to bound, and neither bound is the other's substitute -- a page of
# boilerplate shrinks under conversion and a page of dense tables grows.
class HtmlToMarkdown
  @base : URI?

  INLINE_TEXT_TAGS = {"span", "a", "b", "i", "u", "em", "small", "big",
                      "del", "ins", "sub", "sup", "code", "label"}

  INLINE_WRAP = {"b" => "**", "strong" => "**", "i" => "_", "em" => "_",
                 "del" => "~~", "sup" => "^", "sub" => "~"}

  HEADING_PREFIX = {"h1" => "# ", "h2" => "## ", "h3" => "### ",
                    "h4" => "#### ", "h5" => "##### ", "h6" => "###### "}

  # Subtrees dropped entirely: neither their markup nor their text content
  # is rendered. header/footer/aside is a blunt heuristic for page chrome
  # -- it will occasionally strip a legitimate <header> used for an
  # article's own title/byline. Swap for a text-density heuristic if that
  # turns out to matter in practice.
  #
  # nav is deliberately NOT in this set: on documentation sites a <nav> is
  # frequently the page's table of contents, nested inside <main> rather
  # than a sibling of it, so root-selection alone doesn't exclude it.
  # Since this converter feeds an agent that follows links to find more
  # information, dropping that structure is a correctness problem, not
  # just noise.
  STRIP_TAGS = {"script", "style", "head", "noscript", "svg", "form",
                "button", "header", "footer", "aside", "meta", "link"}

  # A `Set` rather than a tuple because this is asked once per element of
  # every table cell, which is the one lookup here that is hot.
  BLOCK_TAGS_IN_CELL = Set{"p", "div", "ul", "ol", "table", "pre",
                           "blockquote", "dl", "h1", "h2", "h3", "h4", "h5", "h6"}

  RAW_TABLE_TAGS = {"table", "thead", "tbody", "tfoot", "tr", "th", "td"}

  private LANGUAGE_CLASS = /\b(?:language|lang)-(\S+)/

  private DISPLAY_NONE = /display\s*:\s*none/i

  private VISIBILITY_HIDDEN = /visibility\s*:\s*hidden/i

  # How much Markdown was written, and whether the walk stopped early.
  record Result, bytes : Int64, truncated : Bool do
    def truncated? : Bool
      truncated
    end
  end

  # An `IO` that refuses to grow past a limit.
  #
  # The overflowing write is dropped rather than partly applied, so what
  # the buffer holds is always a prefix of a complete write.
  private class Capped < IO
    class Overflow < Exception
    end

    def initialize(@io : IO, @limit : Int64)
      @written = 0_i64
    end

    def write(slice : Bytes) : Nil
      raise Overflow.new if @written + slice.size > @limit
      @written += slice.size
      @io.write(slice)
    end

    def read(slice : Bytes) : Int32
      raise NotImplementedError.new("Capped is write-only")
    end
  end

  def self.translate(io : IO, output : IO, base_url : String? = nil, max_bytes : Int64? = nil) : Result
    new(base_url).convert(HTML5.parse(io), output, max_bytes)
  end

  def initialize(base_url : String?)
    @base = base_url.try { |url| URI.parse(url) }
    @started_newline = true
    @list_stack = [] of Symbol
  end

  private def started_newline?
    @started_newline
  end

  # Prefers <main> or <article> as the conversion root when present, so
  # boilerplate outside them is never walked at all.
  #
  # Builds in memory first, because collapsing blank lines and trimming
  # the document need to know whether more content follows.
  protected def convert(doc : HTML5::Node, output : IO, max_bytes : Int64? = nil) : Result
    buffer = IO::Memory.new
    truncated = fill(doc, buffer, max_bytes)
    markdown = finish(buffer.to_s, truncated)
    output << markdown
    Result.new(markdown.bytesize.to_i64, truncated)
  end

  # True when the walk stopped early.
  private def fill(doc : HTML5::Node, buffer : IO::Memory, max_bytes : Int64?) : Bool
    target = max_bytes ? Capped.new(buffer, max_bytes) : buffer
    root = doc.css("main").first? || doc.css("article").first?
    if root
      walk(root, target, inside_pre: false)
    else
      walk_children(doc, target, inside_pre: false)
    end
    false
  rescue Capped::Overflow
    true
  end

  # A truncated document is cut back to its last blank line, so it ends
  # at a block boundary rather than inside a fence or a table.
  private def finish(markdown : String, truncated : Bool) : String
    return markdown.strip unless truncated
    boundary = markdown.rindex("\n\n")
    (boundary ? markdown[0, boundary] : markdown).strip
  end

  private def walk_children(node : HTML5::Node, md : IO, inside_pre : Bool)
    child = node.first_child
    while child
      walk(child, md, inside_pre)
      child = child.next_sibling
    end
  end

  private def walk(node : HTML5::Node, md : IO, inside_pre : Bool)
    return if node.comment? || node.doctype?

    if node.document?
      walk_children(node, md, inside_pre)
      return
    end

    if node.text?
      parent = node.parent
      inline_ctx = !!parent && parent.element? && INLINE_TEXT_TAGS.includes?(parent.data)
      render_text(md, node.data, inside_pre, inline_ctx)
      return
    end

    return unless node.element?
    name = node.data
    return if STRIP_TAGS.includes?(name)
    return if hidden_by_markup?(node)

    render_element(node, name, md, inside_pre)
  end

  # A flat dispatch over tag names: many branches, no nesting, and each
  # one a single call. Splitting it to satisfy the metric would mean
  # inventing a partition and a fallthrough between the halves, which
  # costs the reader more than the branch count does.
  # ameba:disable Metrics/CyclomaticComplexity
  private def render_element(node : HTML5::Node, name : String, md : IO, inside_pre : Bool)
    case name
    when "table"      then render_table(node, md, inside_pre)
    when "a"          then render_anchor(node, md, inside_pre)
    when "img"        then render_image(node, md)
    when "pre"        then render_pre(node, md)
    when "blockquote" then render_blockquote(node, md, inside_pre)
    when "code"       then render_code(node, md, inside_pre)
    when "br"         then render_break(md)
    when "hr"         then render_rule(md)
    when "dt"         then render_term(node, md, inside_pre)
    when "dd"         then render_definition(node, md, inside_pre)
    when "li"         then render_item(node, md, inside_pre)
    when "ul", "ol"   then render_list(node, name, md, inside_pre)
    when "h1", "h2", "h3", "h4", "h5", "h6"
      render_heading(node, name, md, inside_pre)
    when "p", "div", "dl"
      block_boundary(md)
      walk_children(node, md, inside_pre)
      block_boundary(md)
    else
      render_inline(node, name, md, inside_pre)
    end
  end

  private def render_break(md : IO)
    md << '\n' unless started_newline?
    md << '\n'
    @started_newline = true
  end

  private def render_rule(md : IO)
    md << "\n---\n"
    @started_newline = true
  end

  private def render_heading(node : HTML5::Node, name : String, md : IO, inside_pre : Bool)
    block_boundary(md)
    md << HEADING_PREFIX[name]
    walk_children(node, md, inside_pre)
    md << "\n\n"
    @started_newline = true
  end

  private def render_term(node : HTML5::Node, md : IO, inside_pre : Bool)
    md << "**"
    walk_children(node, md, inside_pre)
    md << "**\n"
  end

  private def render_definition(node : HTML5::Node, md : IO, inside_pre : Bool)
    md << "  : "
    walk_children(node, md, inside_pre)
    md << '\n'
  end

  private def render_item(node : HTML5::Node, md : IO, inside_pre : Bool)
    md << '\n' unless started_newline?
    (@list_stack.size - 1).times { md << "    " }
    md << (@list_stack.last? == :ol ? "1. " : "- ")
    walk_children(node, md, inside_pre)
  end

  private def render_list(node : HTML5::Node, name : String, md : IO, inside_pre : Bool)
    block_boundary(md)
    @list_stack.push(name == "ol" ? :ol : :ul)
    walk_children(node, md, inside_pre)
    @list_stack.pop
    block_boundary(md)
  end

  private def render_inline(node : HTML5::Node, name : String, md : IO, inside_pre : Bool)
    wrap = INLINE_WRAP[name]?
    md << wrap if wrap
    walk_children(node, md, inside_pre)
    md << wrap if wrap
  end

  private def render_text(md : IO, content : String, inside_pre : Bool, inline_ctx : Bool)
    if inside_pre
      md << content
      @started_newline = content.ends_with?('\n')
    elsif inline_ctx
      render_inline_text(md, content)
    else
      render_block_text(md, content)
    end
  end

  # Whitespace-only text between inline tags becomes a single space, so
  # that `<span>&nbsp;</span>` separates words instead of vanishing.
  private def render_inline_text(md : IO, content : String)
    text = content.strip
    if text.empty?
      return if content.empty? || started_newline?
      md << ' '
      @started_newline = false
    else
      md << text
      @started_newline = false
    end
  end

  private def render_block_text(md : IO, content : String)
    text = content.lstrip
    return if text.empty?

    trimmed = text.rstrip
    md << ' ' if text.size < content.size && !started_newline?
    md << trimmed
    if text.rindex('\n').nil?
      md << ' ' if trimmed.size < text.size
      @started_newline = false
    else
      md << '\n'
      @started_newline = true
    end
  end

  private def block_boundary(md : IO)
    return if started_newline?
    md << "\n\n"
    @started_newline = true
  end

  private def attr(node : HTML5::Node, name : String) : String?
    node[name]?.try(&.val)
  end

  # Catches elements hidden without fetching or parsing any stylesheet:
  # the "hidden" attribute, and inline display:none / visibility:hidden.
  # Content hidden by a linked or <style> stylesheet is not detected;
  # that needs real cascade resolution, not selector matching.
  private def hidden_by_markup?(node : HTML5::Node) : Bool
    return true if node["hidden"]?
    return false unless style = attr(node, "style")
    !!(DISPLAY_NONE.match(style) || VISIBILITY_HIDDEN.match(style))
  end

  private def render_anchor(node : HTML5::Node, md : IO, inside_pre : Bool)
    md << '['
    walk_children(node, md, inside_pre)
    md << "]("
    if href = attr(node, "href")
      md << resolve(href)
    end
    md << ')'
  end

  private def render_image(node : HTML5::Node, md : IO)
    return unless src = attr(node, "src")
    md << "![" << (attr(node, "alt") || "") << "](" << resolve(src) << ')'
  end

  # Same-origin results come back root-relative, since a page linking
  # heavily within its own site would otherwise repeat "scheme://host" on
  # every link. Cross-origin results stay absolute; there is no shared
  # context to drop.
  private def resolve(url : String) : String
    base = @base
    return url unless base
    absolute = base.resolve(url)
    same_origin?(base, absolute) ? root_relative(absolute) : absolute.to_s
  rescue
    url
  end

  private def same_origin?(first : URI, second : URI) : Bool
    first.scheme == second.scheme && first.host == second.host && first.port == second.port
  end

  private def root_relative(uri : URI) : String
    String.build do |io|
      io << (uri.path.empty? ? "/" : uri.path)
      if query = uri.query
        io << '?' << query
      end
      if fragment = uri.fragment
        io << '#' << fragment
      end
    end
  end

  private def render_code(node : HTML5::Node, md : IO, inside_pre : Bool)
    if inside_pre
      walk_children(node, md, inside_pre)
    else
      md << '`'
      walk_children(node, md, inside_pre)
      md << '`'
    end
  end

  private def render_pre(node : HTML5::Node, md : IO)
    lang = code_language(node)
    md << '\n' unless started_newline?
    md << "```" << lang << '\n'
    walk_children(node, md, inside_pre: true)
    md << '\n' unless started_newline?
    md << "```\n\n"
    @started_newline = true
  end

  private def code_language(pre : HTML5::Node) : String
    child = pre.first_child
    return "" unless child && child.element? && child.data == "code"
    match = LANGUAGE_CLASS.match(attr(child, "class") || "")
    match ? match[1] : ""
  end

  private def render_blockquote(node : HTML5::Node, md : IO, inside_pre : Bool)
    inner = String.build { |builder| walk_children(node, builder, inside_pre) }
    md << '\n' unless started_newline?
    inner.strip.each_line { |line| md << "> " << line << '\n' }
    md << '\n'
    @started_newline = true
  end

  # GFM pipe syntax when every cell holds only inline content, and raw
  # <table> tags -- with cell contents still rendered as Markdown -- when
  # any cell holds block content that pipe syntax cannot represent.
  private def render_table(node : HTML5::Node, md : IO, inside_pre : Bool)
    block_boundary(md)
    if simple_table?(node)
      render_gfm_table(node, md, inside_pre)
    else
      render_raw_table(node, md, inside_pre)
    end
    block_boundary(md)
  end

  private def simple_table?(table : HTML5::Node) : Bool
    (table.css("td") + table.css("th")).all? { |cell| simple_cell?(cell) }
  end

  # One walk of the cell's subtree, rather than one selector query per
  # block tag per cell: an infobox is hundreds of cells, and thirteen
  # queries each was the converter's own recorded hot spot.
  private def simple_cell?(cell : HTML5::Node) : Bool
    child = cell.first_child
    while child
      if child.element?
        return false if BLOCK_TAGS_IN_CELL.includes?(child.data)
        return false unless simple_cell?(child)
      end
      child = child.next_sibling
    end
    true
  end

  private def row_cells(row : HTML5::Node) : Array(HTML5::Node)
    direct_children(row).select { |child| child.element? && (child.data == "td" || child.data == "th") }
  end

  private def direct_children(node : HTML5::Node) : Array(HTML5::Node)
    result = [] of HTML5::Node
    child = node.first_child
    while child
      result << child
      child = child.next_sibling
    end
    result
  end

  private def render_gfm_table(table : HTML5::Node, md : IO, inside_pre : Bool)
    rows = table.css("tr")
    return if rows.empty?
    header = row_cells(rows.first)
    return if header.empty?

    md << "| " << header.map { |cell| cell_text(cell, inside_pre) }.join(" | ") << " |\n"
    md << "|" << " --- |" * header.size << "\n"
    rows[1..].each do |row|
      cells = row_cells(row)
      next if cells.empty?
      md << "| " << cells.map { |cell| cell_text(cell, inside_pre) }.join(" | ") << " |\n"
    end
    @started_newline = true
  end

  private def cell_text(cell : HTML5::Node, inside_pre : Bool) : String
    String.build { |builder| walk_children(cell, builder, inside_pre) }
      .strip.gsub('\n', ' ').gsub("|", "\\|")
  end

  private def render_raw_table(node : HTML5::Node, md : IO, inside_pre : Bool)
    unless node.element? && RAW_TABLE_TAGS.includes?(node.data)
      walk(node, md, inside_pre)
      return
    end

    md << '<' << node.data << '>'
    child = node.first_child
    while child
      render_raw_table(child, md, inside_pre)
      child = child.next_sibling
    end
    md << "</" << node.data << '>'
  end
end
