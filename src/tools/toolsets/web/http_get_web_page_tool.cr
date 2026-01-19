require "json"
require "http"
require "uri"
require "xml"

require "../../built_in_function"

module Tools::Web
  # The `HttpGetWebPageTool` class defines a tool for making HTTP GET requests to retrieve text content.
  class HttpGetWebPageTool < BuiltInFunction
    name "http_get_web_page"

    description <<-DESC
    Makes an HTTP GET request to a given URL that returns text and returns the content type and content.
    It strips line indents and coalesces line breaks for HTML, JSON and XML. Unless asked not to,
    it removes the `head`, `script`, and `style` elements as well as all `class` attributes
    from HTML content. Content size of response must be less than #{MAX_CONTENT_SIZE//1024}K.
    DESC

    param "url", type: Param::Type::Str,
      description: "The URL to GET the web page from.",
      required: true

    param "user_agent", type: Param::Type::Str,
      description: "Optional user agent header; default is Firefox for macOS.",
      required: false

    param "accept", type: Param::Type::Str,
      description: <<-DESCR
      Optionally specify an acceptable content type (e.g. `text/markdown`) to ask the
      server for specific format. Default is none.
      DESCR

    param "preserve_source", type: Param::Type::Bool,
      description: "Optional flag to ask to preserve the content from the server without any attempts to condense the text; default is false."

    runner Runner

    # The Runner class executes the function
    class Runner < LLM::Function::Runner
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:146.0) Gecko/20100101 Firefox/146.0"

      def execute(args : JSON::Any) : String
        url = args["url"].as_s? || return error_response("The required URL was not specified")
        user_agent = args["user_agent"]?.try(&.as_s?) || USER_AGENT
        preserve_source = args["preserve_source"]? || false
        accept = args["accept"]?.try(&.as_s?) || nil

        headers = HTTP::Headers{
          "User-Agent" => user_agent,
        }
        headers.add("Accept", accept) if accept
        fetch(url, headers, preserve_source)
      end

      # Setup the HTTP request and process content if appropriate,
      # returning error or success JSON.
      private def fetch(url, headers, preserve_source)
        HTTP::Client.get(url, headers) do |response|
          if response.status_code == 200
            if (ctype = response.content_type) && Web.text?(ctype)
              content = gather_content(response)
              if content.size <= MAX_CONTENT_SIZE
                success_response(ctype, content, preserve_source)
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
      def success_response(content_type, content, preserve_source)
        reduced_content = unless preserve_source
          case content_type
          when .ends_with?("html") then reduce_html(content)
          when .ends_with?("json") then reduce_line_indents_and_breaks(content)
          when .ends_with?("xml")  then reduce_line_indents_and_breaks(content)
          end
        end
        {
          content_type: content_type,
          body:         reduced_content || content,
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

      private def reduce_html(content)
        content = reduce_line_indents_and_breaks(content)
        # Remove head, script, style tags and their contents
        content = content.gsub(/<head\b[^<]*>.*?<\/head>/mi, "")
        content = content.gsub(/<script\b[^<]*>.*?<\/script>/mi, "")
        content = content.gsub(/<style\b[^<]*>.*?<\/style>/mi, "")
        # Remove class attributes from all elements
        content = content.gsub(/class\s*=\s*'[^']*'/i, "")
        content = content.gsub(/class\s*=\s*"[^"]*"/i, "")
        content
      end
    end
  end
end
