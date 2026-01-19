require "json"
require "http"
require "uri"
require "xml"

require "../../built_in_function"
require "../../../sucre/html_to_markdown"

module Tools::Web
  # The `HttpGetWebAsMarkdownTool` class defines a tool for making HTTP GET requests to retrieve web pages as Markdown.
  class HttpGetWebAsMarkdownTool < BuiltInFunction
    name "http_get_web_page_as_markdown"

    description <<-DESC
    Makes an HTTP GET request to a given web site URL that returns the content
    as markdown, either because the website supports returning markdown or by converting
    the HTML to markdown. If the text content from the web site is not HTML or markdown,
    the tool returns a markdown document with the web page content within a code block.
    DESC

    param "url", type: Param::Type::Str,
      description: "The URL to GET the web page from.",
      required: true

    param "user_agent", type: Param::Type::Str,
      description: "Optional user agent header; default is Firefox for macOS.",
      required: false

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:146.0) Gecko/20100101 Firefox/146.0"

      def execute(args : JSON::Any) : String
        url = args["url"].as_s? || return error_response("The required URL was not specified")
        user_agent = args["user_agent"]?.try(&.as_s?) || USER_AGENT

        headers = HTTP::Headers{
          "User-Agent" => user_agent,
          "Accept"     => "text/markdown",
        }
        fetch(url, headers)
      end

      # Setup the HTTP request and process content if appropriate,
      # returning error or success JSON.
      private def fetch(url, headers)
        HTTP::Client.get(url, headers) do |response|
          if response.status_code == 200
            case ctype = response.content_type
            when Nil
              error_response("HTTP response did not return valid content type")
            when .ends_with?("/markdown")
              success_markdown(response.body)
            when .ends_with?("/html")
              content = HtmlToMarkdown.translate(response.body_io)
              success_markdown(content)
            else
              if Web.text?(ctype)
                success_text(response, ctype)
              else
                error_response("HTTP response did not return text content; it's content type was: #{ctype}")
              end
            end
          else
            error_response("HTTP request failed with status: #{response.status_code}")
          end
        end
      rescue e
        error_response("An error occurred while making the HTTP request: #{e.message}")
      end

      # Retrieve content from the HTTP response, stopping when
      # content size exceeds MAX_CONTENT_SIZE.
      private def gather_content(response)
        content_size = 0
        String.build do |builder|
          # Line by line, gather content up to max size
          response.body_io.each_line(chomp: false) do |line|
            builder << line
            content_size += line.size
            break if content_size > MAX_CONTENT_SIZE
          end
        end
      end

      # Wraps up the content in a Markdown code block, specifying a content type
      # hint if we can figure one out
      def success_text(response, content_type)
        markdown = String.build do |io|
          if format_hint = text_format_name?(content_type)
            io.puts("```#{format_hint.downcase}")
          else
            io.puts("```")
          end
          size = 0
          response.body_io.each_line do |line|
            if (size += line.size) > MAX_CONTENT_SIZE
              return error_response("Received content > #{MAX_CONTENT_SIZE}. Response is too big.")
            end
            io.puts line
          end
          io.puts("```")
        end
        success_markdown(markdown)
      end

      # Try and determine a format name based on content type
      # that we can use as content type hint for markdown code fence.
      private def text_format_name?(content_type) : String?
        if content_type.starts_with?("text/x-")
          content_type.split("/x-", limit: 2).last
        elsif found = TEXT_CTYPE_SUFFIXES.find { |suffix| content_type.ends_with?(suffix) }
          found.lchop
        end
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end

      # Create a successful response with markdown content
      def success_markdown(content)
        {
          markdown: content,
        }.to_json
      end
    end
  end
end
