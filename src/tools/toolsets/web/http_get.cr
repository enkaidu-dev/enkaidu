require "../../built_in_function"
require "../../../sucre/host_policy"

module Tools::Web
  abstract class HttpGet < BuiltInFunction
    @host_policy : HostPolicy?

    # Retrieve a setting if present, or nil
    private def extract_setting(name)
      case value = (settings.try &.[name]?)
      when Array(String) then value
      when String        then [value]
      end
    end

    def host_policy : HostPolicy
      @host_policy ||= HostPolicy.new do |config|
        config.allowed_hosts = extract_setting("allowed_hosts") || [] of String
        config.allow_private_hosts = settings.try &.["allow_private_hosts"]? == true
        config.denied_hosts = extract_setting("denied_hosts") || [] of String
      end
    end

    # The Runner class executes the function
    abstract class BaseRunner < LLM::Function::Runner
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:146.0) Gecko/20100101 Firefox/146.0"

      protected getter func : HttpGet

      def initialize(@func); end

      def ask_user_permission(url)
        func.renderer.user_permission_question(
          description: "The agent's AI model wants to fetch the following URL.",
          subject: url.to_s
        )
      end

      # Create an error response as a JSON string
      def error_response(message : String)
        {error: message}.to_json
      end

      MAX_REDIRECTS = 3

      # GET URL, redirect up to `MAX_REDIRECTS` time.
      protected def http_get(url, headers, &)
        count_redirects = 0
        while count_redirects < MAX_REDIRECTS
          HTTP::Client.get(url, headers) do |response|
            case response.status_code
            when 301, 307, 308
              count_redirects += 1
              url = response.headers["Location"]
            when 200
              return yield response
            end
          end
        end
        raise Exception.new("Too many HTTP redirects; aborting")
      end

      # Create an error response as a JSON string
      def error_response(error : HostPolicy::Error)
        {
          error:      error.message,
          suggestion: error.suggestion,
        }.to_json
      end
    end
  end
end
