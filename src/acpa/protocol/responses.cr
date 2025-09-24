require "./capabilities"

module ACPA
  # Base class for outgoing JSON RPC responses from ACP agent to the editor
  abstract class JsonRpcResponse(R) < JsonRpcMessage
    getter result : R

    def initialize(@id, @result); end

    check_if_clean_with result
  end

  # Outgoing JSON RPC responses are defined in this module
  module Response
    class InitResult < JsonEntity
      @[JSON::Field(key: "protocolVersion")]
      getter protocol_version : Int32

      @[JSON::Field(key: "agentCapabilities")]
      getter agent_capabilities : Capabilities::Agent

      check_if_clean_with agent_capabilities

      def initialize(@agent_capabilities, @protocol_version = PROTOCOL_VERSION)
        super()
      end
    end

    class Initialize < JsonRpcResponse(InitResult)
      def initialize(id, result)
        super(id, "initialize", result)
      end
    end
  end
end
