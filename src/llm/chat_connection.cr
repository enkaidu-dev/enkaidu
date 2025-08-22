require "http/client"
require "uri"

require "./chat"

module LLM
  abstract class ChatConnection
    protected property model : String? = nil

    def initialize
      @client = HTTP::Client.new(URI.parse(url))
    end

    protected def post_and_stream(body, &)
      @client.post(path, headers,
        body: body) do |resp|
        yield resp
      end
    end

    protected abstract def url : String

    protected abstract def path : String

    protected abstract def headers : HTTP::Headers

    abstract def new_chat(&) : Chat
  end
end
