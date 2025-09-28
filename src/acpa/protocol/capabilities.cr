require "../../sucre/json_rpc"

module ACPA
  # Capability JSON data types are defined in this module
  module Capabilities
    class FileSystem < JsonRpc::Entity
      @[JSON::Field(key: "readTextFile")]
      getter? read_text_file : Bool = false

      @[JSON::Field(key: "writeTextFile")]
      getter? write_text_file : Bool = false
    end

    # Incoming client capabilities from the editor
    class Client < JsonRpc::Entity
      getter fs : FileSystem

      check_if_clean_with fs
    end

    class Prompt < JsonRpc::Entity
      @[JSON::Field(key: "image")]
      getter? image = false

      @[JSON::Field(key: "audio")]
      getter? audio = false

      @[JSON::Field(key: "embeddedContext")]
      getter? embedded_context = false
    end

    class Mcp < JsonRpc::Entity
      @[JSON::Field(key: "http")]
      getter? http = false

      @[JSON::Field(key: "sse")]
      getter? sse = false
    end

    # Outgoing ACP agent capabilities to the editor
    class Agent < JsonRpc::Entity
      @[JSON::Field(key: "loadSession")]
      getter? load_session = false

      @[JSON::Field(key: "promptCapabilities")]
      getter prompt_capabilities : Prompt

      @[JSON::Field(key: "mcpCapabilities")]
      getter mcp_capabilities : Mcp

      check_if_clean_with prompt_capabilities, mcp_capabilities
    end
  end
end
