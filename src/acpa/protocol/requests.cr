require "./capabilities"

module ACPA
  # Base class for incoming JSON RPC requests from editor to the ACP agent
  abstract class JsonRpcRequest(P) < JsonRpcMessage
    use_json_discriminator "method", {
      initialize: Request::Initialize,
    }

    getter method : String
    getter params : P

    check_if_clean_with params
  end

  abstract class ContentBlock < JsonEntity
    use_json_discriminator "type", {
      text: TextContent,
    }
    getter type : String
  end

  class TextContent < ContentBlock
    getter text : String
  end

  # Incoming JSON RPC requests are defined in this module
  module Request
    class InitParams < JsonEntity
      @[JSON::Field(key: "protocolVersion")]
      getter protocol_version : Int32

      @[JSON::Field(key: "clientCapabilities")]
      getter client_capabilities : Capabilities::Client

      check_if_clean_with client_capabilities
    end

    class Initialize < JsonRpcRequest(InitParams); end

    class PromptParams < JsonEntity
      @[JSON::Field(key: "sessionId")]
      getter session_id : String
      getter prompt : Array(ContentBlock)
    end

    class Prompt < JsonRpcRequest(PromptParams); end
  end
end
