require "../../sucre/json_rpc"

module ACPA
  # Outgoing ACP responses
  abstract class Response(R) < JsonRpc::Response(R)
    class InitResult < JsonRpc::Entity
      @[JSON::Field(key: "protocolVersion")]
      getter protocol_version : Int32

      @[JSON::Field(key: "agentCapabilities")]
      getter agent_capabilities : Capabilities::Agent

      check_if_clean_with agent_capabilities

      def initialize(@agent_capabilities, @protocol_version = PROTOCOL_VERSION)
        super()
      end
    end

    class Initialize < Response(InitResult)
      def initialize(id, result)
        super(id, "initialize", result)
      end
    end
  end
end
