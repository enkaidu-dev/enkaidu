require "json"

module ACPA
  PROTOCOL_VERSION = 1

  # Common serializable JSON entity
  abstract class JsonEntity
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    def clean?
      json_unmapped.empty?
    end

    def dirty?
      !clean?
    end

    macro check_if_clean_with(*props)
      def clean?
        super && {{ (props.map { |prop| "#{prop}.clean?" }).join(" && ").id }}
      end
    end
  end

  # A message is the basic unit of JSON RPC
  abstract class JsonRpcMessage < JsonEntity
    getter jsonrpc = "2.0"
    getter id : Int32
  end
end
