require "json"
require "http"
require "uri"
require "xml"

require "../../built_in_function"

module Tools::Web
  # The `HttpGetTextTool` class defines a tool for making HTTP GET requests to retrieve text content.
  class HttpGetTextTool < BuiltInFunction
    MAX_CONTENT_SIZE = 256*1024

    name "http_get_text_tool"

    description <<-DESC
    Makes an HTTP GET request to a given URL that returns text, andreturns the content type and content.
    It strips line indents and coalesces line breaks for HTML, JSON and XML. Unless asked not to,
    it removes the `head`, `script`, and `style` elements as well as all `class` attributes
    from HTML content. Content size of response must be less than #{MAX_CONTENT_SIZE//1024}K.
    DESC

    param "url", type: Param::Type::Str,
      description: "The URL to GET text from.",
      required: true

    param "user_agent", type: Param::Type::Str,
      description: "Optional user agent header; default is Firefox for macOS.",
      required: false

    param "preserve_html", type: Param::Type::Bool,
      description: "Optional flag to preserve all the HTML content; default is false."

    param "accept", type: Param::Type::Str,
      description: <<-DESCR
      Optionally specify an acceptable content type (e.g. `text/markdown`) to ask the
      server for specific format. Default is none.
      DESCR

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:146.0) Gecko/20100101 Firefox/146.0"

      def execute(args : JSON::Any) : String
        url = args["url"].as_s? || return error_response("The required URL was not specified")
        user_agent = args["user_agent"]?.try(&.as_s?) || USER_AGENT
        preserve_html = args["preserve_html"]? || false
        accept = args["accept"]?.try(&.as_s?) || nil

        headers = HTTP::Headers{
          "User-Agent" => user_agent,
        }
        headers.add("Accept", accept) if accept
        fetch(url, headers, preserve_html)
      end

      # Setup the HTTP request and process content if appropriate,
      # returning error or success JSON.
      private def fetch(url, headers, preserve_html)
        HTTP::Client.get(url, headers) do |response|
          if response.status_code == 200
            if (ctype = response.content_type) && text?(ctype)
              content = gather_content(response)
              if content.size <= MAX_CONTENT_SIZE
                success_response(ctype, content, preserve_html)
              else
                error_response("Received content > #{MAX_CONTENT_SIZE}. Response is too big.")
              end
            else
              error_response("HTTP request did not return text content; it's content type was: #{ctype}")
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

      # Create a success response as a JSON string
      def success_response(content_type, content, preserve_html)
        reduced_content = case content_type
                          when .ends_with?("html") then reduce_html(content, preserve_html)
                          when .ends_with?("json") then reduce_line_indents_and_breaks(content)
                          when .ends_with?("xml")  then reduce_line_indents_and_breaks(content)
                          else
                            content
                          end
        {
          content_type: content_type,
          body:         reduced_content,
        }.to_json
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end

      #
      # FUTURE ME - can we optimize these to strip / reduce content without
      #             wasting so much memory with each regex?
      #

      private def reduce_line_indents_and_breaks(content)
        # Strips all line indents completely
        content = content.gsub(/^\s+/mi, "")
        # Replaces line break runs with a single newline
        content.gsub(/[\n\r]+/, "\n")
      end

      private def reduce_html(content, preserve_html)
        content = reduce_line_indents_and_breaks(content)
        unless preserve_html
          # Remove head, script, style tags and their contents
          content = content.gsub(/<head\b[^<]*>.*?<\/head>/mi, "")
          content = content.gsub(/<script\b[^<]*>.*?<\/script>/mi, "")
          content = content.gsub(/<style\b[^<]*>.*?<\/style>/mi, "")
          # Remove class attributes from all elements
          content = content.gsub(/class\s*=\s*'[^']*'/i, "")
          content = content.gsub(/class\s*=\s*"[^"]*"/i, "")
        end
        content
      end

      TEXT_CTYPE_PREFIXES = [
        "text/",
      ]
      TEXT_CTYPE_SUFFIXES = [
        "/json",
        "/xml",
      ]

      private def text?(content_type)
        TEXT_CTYPE_PREFIXES.any? { |prefix| content_type.starts_with?(prefix) } ||
          TEXT_CTYPE_SUFFIXES.any? { |suffix| content_type.ends_with?(suffix) }
      end
    end
  end
end
