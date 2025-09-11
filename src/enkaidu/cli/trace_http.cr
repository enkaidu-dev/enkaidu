require "http"
require "colorize"

class HTTP::Client
  @@trace_http = false
  @@count = 0

  def self.trace_http=(value : Bool)
    @@trace_http = value
  end

  def_around_exec do |request|
    if @@trace_http
      STDERR.puts "--> HTTP request #{".." * @@count} #{request.method} #{request.path}".colorize(:cyan)
      @@count += 1
    end
    response = yield
    if @@trace_http
      @@count -= 1
      if response.is_a? HTTP::Client::Response
        STDERR.puts "<-- HTTP response #{".." * @@count} #{request.method} #{request.headers["Host"]?} #{request.path} #{response.status_code} #{response.status} #{response.content_type}".colorize(:cyan)
      else
        STDERR.puts "<-- HTTP response #{".." * @@count} #{response.inspect}".colorize(:cyan)
        begin
          raise Exception.new("Response is not HTTP::Client::Response")
        rescue ex
          STDERR.puts ex.inspect_with_backtrace
        end
      end
    end
    response
  end
end
