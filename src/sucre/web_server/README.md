# API Server

A simple routable HTTP server that will be used to build the API engine for Enkaidu in server mode.

## TODO

- [ ] Make the handler API even simpler
- [ ] How to register a handler that takes input and output as JSON::Serializable objects and not have to worry about requests and responses?

## Example

```cr
require "json"
require "./src/sucre/api_server/server"

s = Server.new(8080)

s.before_all do |_, resp|
  resp.content_type = "application/json"
end

s.get "/quit" do |_, resp|
  resp.print "{ }"
  s.close
end

s.get "/error" do |_, resp|
  raise ArgumentError.new("Unexpected /error argument")
end

s.get "/hello" do |req, resp|
  q = req.query_params
  resp.print(JSON.build do |jb|
    jb.object do
      if name = q["name"]?
        jb.field "message", "Hello, #{name}!"
      else
        jb.field "message", "Hello! Bonjour!"
      end
    end
  end)
end

s.start
s.join
```