require "colorize"

module Enkaidu::Console
  class Style
    getter bg : Colorize::Color?
    getter fg : Colorize::Color?
    getter format : Array(Colorize::Mode)?

    def initialize(@bg = nil,
                   @fg = nil,
                   @format = nil); end
  end

  enum Category
    Response
    Info
    Warning
    Error
    BeforeQuery
    QuerySyntaxCommand
    QuerySyntaxPath
    QuerySyntaxMacro
    QueryPrefixByUser
    QueryPrefixByQueue
    QueryFeedback
    AfterReply
    ConfirmQuestion
    ConfirmContent
    ConfirmInput
    PromptQuestion
    PromptContent
    PromptInput
    SessionBanner
    SessionOpen
    SessionClose
    ToolCallReason
    ToolCallDetail
    ThinkingProgress
    ThinkingContent
    McpAction
    McpFeedback
  end

  class StyleSheet
    @styles = {} of Category => Style

    private def initialize; end

    def self.create(&)
      sheet = self.new
      with sheet yield
      sheet
    end

    def add(key : Category, style : Style)
      @styles[key] = style
    end

    private def parse_color(value)
      case value
      when Symbol, String             then Colorize::ColorANSI.parse(value.to_s)
      when UInt8                      then Colorize::Color256.new(value)
      when Tuple(UInt8, UInt8, UInt8) then Colorize::ColorRGB.new(*value)
      end
    end

    private def parse_mode(values)
      return nil unless values
      values.map do |value|
        Colorize::Mode.parse(value.to_s)
      end
    end

    def add(key : Symbol | String, style : NamedTuple | Hash)
      cat = Category.parse(key.to_s)
      fg = parse_color(style["fg"]? || style[:fg]?)
      bg = parse_color(style["bg"]? || style[:bg]?)
      fmt = parse_mode(style["format"]? || style[:format]?)
      add(cat, Style.new(bg: bg, fg: fg, format: fmt))
    end

    # Return `nil` if unable to find style for category, or
    # style-applied text on success
    def apply?(key : Symbol | String | Category, text : String) : String?
      if ((cat = key).is_a? Category) || (cat = Category.parse?(key.to_s))
        if style = @styles[cat]?
          c = text.colorize
          if fg = style.fg
            c.fore(fg)
          end
          if bg = style.bg
            c.back(bg)
          end
          if modes = style.format
            modes.each do |mode|
              c.mode(mode)
            end
          end
          c.to_s
        end
      end
    end

    # ------------------------------------
    @@default_style_sheet : self?

    # A default style sheet with all categories configured
    def self.default
      @@default_style_sheet ||= Console::StyleSheet.create do
        add :response, {fg: :white, format: [:bold]}
        add :info, {fg: :cyan}
        add :warning, {fg: :light_red}
        add :error, {fg: :red}
        add :before_query, {fg: :yellow}
        add :query_syntax_command, {fg: :light_red, format: [:italic]}
        add :query_syntax_macro, {fg: :light_red, format: [:italic]}
        add :query_syntax_path, {fg: :light_blue}
        add :after_reply, {fg: :yellow}
        add :query_prefix_by_user, {fg: :yellow}
        add :query_prefix_by_queue, {fg: :magenta}
        add :query_feedback, {fg: :green}
        add :confirm_question, {fg: :white}
        add :confirm_content, {fg: :red, format: [:bold]}
        add :confirm_input, {fg: :white, format: [:bold]}
        add :session_banner, {fg: :light_green}
        add :session_open, {fg: :white}
        add :session_close, {fg: :white}
        add :tool_call_reason, {fg: :green}
        add :tool_call_detail, {fg: :light_green, format: [:italic]}
        add :thinking_progress, {fg: :dark_gray, format: [:italic]}
        add :thinking_content, {fg: :dark_gray, format: [:italic]}
        add :prompt_question, {fg: :cyan}
        add :prompt_content, {fg: :cyan, format: [:italic]}
        add :prompt_input, {fg: :white, format: [:bold]}
        add :mcp_feedback, {fg: :light_blue}
        add :mcp_action, {fg: :light_blue, format: [:italic]}
      end
    end
  end

  module StyleApplicator
    getter style_sheet : StyleSheet?

    # Set a stylesheet from the configuration's stylesheet definition
    def style_sheet=(config_ss : Config::Console::StyleSheet)
      @style_sheet = StyleSheet.create do
        config_ss.each do |key, value|
          add key, value
        end
      end
    end

    # Set a stylesheet from the configuration's stylesheet definition
    def style_sheet=(ss : StyleSheet)
      @style_sheet = ss
    end

    # Apply a style based on the category symbol
    def fmt(cat : Symbol | Category, text : String) : String
      result = if sheet = style_sheet
                 sheet.apply?(cat, text)
               end
      result || StyleSheet.default.apply?(cat, text) || text
    rescue
      # Return text as is if formatting fails
      text
    end
  end
end
