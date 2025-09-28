require "json"

module JsonRpc
  PROTOCOL_VERSION = "2.0"

  # Common serializable JSON RPC entity
  abstract class Entity
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    # Returns true if there are no unmapped properties after
    # parsing `#from_json`
    def clean?
      json_unmapped.empty?
    end

    # Returns true if there are unmapped properties after
    # parsing `#from_json`
    def dirty?
      !clean?
    end

    # Call this when subclassing an entity with properties that
    # are also JSON entities to define a `#clean?` method that
    # includes those properties in the check.
    macro check_if_clean_with(*props)
      def clean?
        super && {{ (props.map { |prop| "#{prop}.clean?" }).join(" && ").id }}
      end
    end
  end

  # Base class for incoming JSON RPC requests from editor to the ACP agent
  abstract class Request(P) < Entity
    getter jsonrpc = PROTOCOL_VERSION
    getter id : Int32
    getter method : String
    getter params : P

    check_if_clean_with params
  end

  # Base class for outgoing JSON RPC responses from ACP agent to the editor
  abstract class Response(R) < Entity
    getter jsonrpc = PROTOCOL_VERSION
    getter id : Int32
    getter result : R

    def initialize(@id, @result); end

    check_if_clean_with result
  end

  # Base class for outgoing JSON RPC notifications from ACP agent to the editor
  abstract class Notification(P) < Entity
    getter jsonrpc = PROTOCOL_VERSION
    getter method : String
    getter params : P

    def initialize(@method, @params); end

    check_if_clean_with params
  end
end
