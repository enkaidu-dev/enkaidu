require "json"

module MCPC
  # MCP Session, with support for tools.
  class Session
    getter requests = 0
    property protocol_version

    def initialize(@protocol_version = "2024-11-05")
    end

    def body_initialize
      setup_request "initialize" do |json|
        setup_params(json) do
          json.field "capabilities" do
            json.object do
              json.field "tools" do
                json.object do
                  json.field "listChanged", true
                end
              end
            end
          end
          setup_client_info(json)
        end
      end
    end

    def body_notify_initialized
      setup_notification "initialized" { |_| }
    end

    def body_roots_list
      setup_request "roots/list" do |json|
        setup_params(json) do
          setup_client_info(json)
        end
      end
    end

    def body_tools_list
      setup_request "tools/list" do |json|
        setup_params(json) do
          setup_client_info(json)
        end
      end
    end

    def body_tools_call(name : String, args : Hash(String, String | Number | Bool | JSON::Any))
      setup_request "tools/call" do |json|
        setup_params(json) do
          json.field "name", name
          json.field "arguments" do
            json.object do
              args.each do |k, v|
                case v
                when JSON::Any
                  json.field k do
                    v.to_json(json)
                  end
                else
                  json.field k, v
                end
              end
            end
          end
          setup_client_info(json)
        end
      end
    end

    private def next_id!
      @requests += 1
    end

    private def setup_params(json, &)
      json.field "params" do
        json.object do
          json.field "protocolVersion", protocol_version
          yield
        end
      end
    end

    private def setup_request(method : String, & : JSON::Builder ->) : String
      JSON.build do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "id", next_id!
          json.field "method", method
          yield(json)
        end
      end
    end

    private def setup_notification(method_suffix : String, & : JSON::Builder ->) : String
      JSON.build do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "method", "notifications/#{method_suffix}"
          yield(json)
        end
      end
    end

    private def setup_client_info(json)
      json.field "clientInfo" do
        json.object do
          json.field "name", ABOUT[:name]
          json.field "version", ABOUT[:version]
        end
      end
    end
  end
end
