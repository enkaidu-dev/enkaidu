require "../../sucre/json_rpc"
require "./content"

module ACPA
  # Incoming JSON RPC requests are defined in this module
  abstract class Request(P) < JsonRpc::Request(P)
    use_json_discriminator "method", {
      initialize: Request::Initialize,
    }

    class InitParams < JsonRpc::Entity
      @[JSON::Field(key: "protocolVersion")]
      getter protocol_version : Int32

      @[JSON::Field(key: "clientCapabilities")]
      getter client_capabilities : Capabilities::Client

      check_if_clean_with client_capabilities
    end

    class Initialize < Request(InitParams); end

    class PromptParams < JsonRpc::Entity
      @[JSON::Field(key: "sessionId")]
      getter session_id : String
      getter prompt : Array(ContentBlock)
    end

    class Prompt < Request(PromptParams); end

    alias ParamTypes = InitParams | PromptParams
  end
end
