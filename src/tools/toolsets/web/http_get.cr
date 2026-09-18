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
        config.allowed_hosts = extract_setting("allowed_hosts")
        config.allow_private_hosts = settings.try &.["allow_private_hosts"]? == true
        config.denied_hosts = extract_setting("denied_hosts") || [] of String
      end
    end

    # The Runner class executes the function
    abstract class BaseRunner < LLM::Function::Runner
      USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:146.0) Gecko/20100101 Firefox/146.0"

      protected getter func : HttpGet

      def initialize(@func); end

      # Create an error response as a JSON string
      def error_response(message : String)
        {error: message}.to_json
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
