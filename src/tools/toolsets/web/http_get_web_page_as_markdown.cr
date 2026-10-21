require "json"
require "http"
require "uri"
require "xml"

require "./http_get"
require "../../../sucre/html_to_markdown"

module Tools::Web
  # The `HttpGetWebAsMarkdownTool` class defines a tool for making HTTP GET requests to retrieve web pages as Markdown.
  class HttpGetWebAsMarkdownTool < HttpGet
    name "http_get_web_page_as_markdown"
    side_effects SideEffects::NetRead

    description <<-DESC
      Fetches a web site by its URL and returns the content as markdown, either because the website supports
      returning markdown or by converting the HTML to markdown. For other kinds of text, the tool
      returns a markdown document with the web page content within a code block. If content exceeds
      #{MAX_CONTENT_SIZE} bytes, it truncates the content and includes a `truncated: true` property.
      DESC

    param "url", type: Param::Type::Str,
      description: "The URL to GET the web page from.",
      required: true

    param "user_agent", type: Param::Type::Str,
      description: "Optional user agent header; default is Firefox for macOS.",
      required: false

    param "save_as_file", type: Param::Type::Str,
      description: <<-DESCR
        Optionally specify a file to save entire web page as Markdown.
        If this is a temporary file save it in `tmp/` folder.
        DESCR

    param "overwrite", type: Param::Type::Bool, required: false,
      description: "Optional. Set to true to overwrite existing file, applicable if saving as a file. Default is false."

    # Replace `runner` macro to create with self
    def new_runner : Runner
      Runner.new(self)
    end

    # The Runner class executes the function
    class Runner < HttpGet::BaseRunner
      include FileHelper

      def execute(args : JSON::Any) : String
        url = args["url"]?.try(&.as_s?) || return error_response("The required URL was not specified")
        user_agent = args["user_agent"]?.try(&.as_s?) || USER_AGENT
        save_as_file = args["save_as_file"]?.try(&.as_s?)

        save_path = begin
          overwrite = args["overwrite"]?.try(&.as_bool?) || false
          confirm_save_path(save_as_file, overwrite)
        rescue ex
          return error_response(ex.to_s)
        end

        headers = HTTP::Headers{
          "User-Agent" => user_agent,
          "Accept"     => "text/markdown",
        }
        uri = URI.parse(url)
        begin
          func.host_policy.check!(uri)
        rescue HostPolicy::HostUnknownError
          perm = ask_user_permission(url)
          if host = uri.host
            if perm.approved?
              func.host_policy.always_allow(host) if perm.remember?
            else
              func.host_policy.always_deny(host) if perm.remember?
              raise HostPolicy::HostDeniedError.new(
                "#{host} is not a host this tool may fetch",
                "User has denied permission to fetch this URL.")
            end
          end
        end
        fetch(url, headers, save_path)
      rescue ex : HostPolicy::Error
        error_response(ex)
      end

      private def confirm_save_path(save_as_file : String?, overwrite : Bool) : String?
        return unless save_as_file

        full = resolve_path(save_as_file)

        unless within_current_directory?(full)
          raise ArgumentError.new("Access to the specified path '#{save_as_file}' is not allowed.")
        end

        if file_exists?(full)
          if overwrite
            if path_in_deleted_files_folder?(full)
              raise ArgumentError.new("Cannot overwrite files in the `#{DELETED_FILES_PATH}` folder.")
            end
          else
            raise ArgumentError.new("The file '#{save_as_file}' already exists.")
          end
        end

        full
      end

      # Ensure directory-sub-tree for file exists
      private def write_to_file(save_path : String, &)
        parent = Path.new(save_path).parent
        Dir.mkdir_p(parent) unless Dir.exists?(parent)
        File.open(save_path, "w") do |file|
          yield file
        end
      end

      # Setup the HTTP request and process content if appropriate,
      # returning error or success JSON.
      private def fetch(url, headers, save_path : String? = nil)
        http_get(url, headers) do |response|
          if response.status_code == 200
            case ctype = response.content_type
            when Nil                      then error_response("HTTP response did not return valid content type")
            when .ends_with?("/markdown") then receive_markdown(url, response, save_path)
            when .ends_with?("/html")     then receive_html(url, response, save_path)
            else
              if Web.text?(ctype)
                receive_text(url, response, ctype, save_path)
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

      def receive_html(url, response, save_path)
        if save_path
          write_to_file(save_path) do |file|
            HtmlToMarkdown.translate(response.body_io, file)
          end
          success_saved_markdown(url, save_path)
        else
          truncated = false
          content = String.build do |io|
            result = HtmlToMarkdown.translate(response.body_io, io, max_bytes: MAX_CONTENT_SIZE)
            truncated = result.truncated?
          end
          success_markdown(url, content, truncated)
        end
      end

      def receive_markdown(url, response, save_path)
        if save_path
          write_to_file(save_path) do |file|
            response.body_io.each_line do |line|
              file.puts(line)
            end
          end
          success_saved_markdown(url, save_path)
        else
          truncated = false
          markdown = String.build do |io|
            size = 0
            response.body_io.each_line do |line|
              if (size += line.size) > MAX_CONTENT_SIZE
                truncated = true
                break
              end
              io.puts line
            end
          end
          success_markdown(url, markdown, truncated)
        end
      end

      # Wraps up the content in a Markdown code block, specifying a content type
      # hint if we can figure one out
      def receive_text(url, response, content_type, save_path)
        format_hint = text_format_name?(content_type).try(&.downcase) || ""
        if save_path
          write_to_file(save_path) do |file|
            file << "```"
            file.puts format_hint
            response.body_io.each_line do |line|
              file.puts(line)
            end
            file << "```"
          end
          success_saved_markdown(url, save_path)
        else
          truncated = false
          markdown = String.build do |io|
            if format_hint = text_format_name?(content_type)
              io.puts("```#{format_hint.downcase}")
            else
              io.puts("```")
            end
            size = 0
            response.body_io.each_line do |line|
              if (size += line.size) > MAX_CONTENT_SIZE
                truncated = true
                break
              end
              io.puts line
            end
            io.puts("```")
          end
          success_markdown(url, markdown, truncated)
        end
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

      # Create a successful response with markdown content
      def success_markdown(url, content, truncated)
        {
          url:       url,
          truncated: truncated,
          markdown:  content,
        }.to_json
      end

      # Create a successful response with referencence to saved markdown content
      def success_saved_markdown(url, path)
        {
          url:           url,
          saved_as_file: path,
        }.to_json
      end
    end
  end
end
