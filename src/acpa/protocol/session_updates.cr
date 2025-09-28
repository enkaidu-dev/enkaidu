require "../../sucre/json_rpc"
require "./content"

module ACPA
  abstract class Notification(P) < JsonRpc::Notification(P)
    use_json_discriminator "method", {
      "session/update": SessionUpdate::Notification,
    }
  end

  # The different kinds of session update blocks, discriminated by the unfortunately
  # named `SessionUpdateBlock#session_update` property (per the ACP spec)
  module SessionUpdate
    # Session update notification parameters sent by the agent
    class Params < JsonRpc::Entity
      @[JSON::Field(key: "sessionId")]
      getter session_id : String

      getter update : UpdateBlock

      check_if_clean_with update

      def initialize(@session_id, @update)
        super("session/update")
      end
    end

    class Notification < ACPA::Notification(Params)
      def initialize(session_id, update : UpdateBlock)
        super(
          "session/update",
          Params.new(session_id, update))
      end
    end

    # The value type for the `update:` property in a `SessionUpdateNotification`
    abstract class UpdateBlock < JsonRpc::Entity
      @[JSON::Field(key: "sessionUpdate")]
      getter session_update : String

      def initialize(@session_update); end
    end

    # An update with text content
    abstract class ContentUpdate < UpdateBlock
      getter content : ContentBlock

      check_if_clean_with content

      def initialize(session_update_type, @content)
        super(session_update_type)
        @content = TextContent.new(text)
      end
    end

    class UserMessageChunk < ContentUpdate
      def initialize(content)
        super("user_message_chunk", content)
      end
    end

    class AgentMessageChunk < ContentUpdate
      def initialize(content)
        super("agent_message_chunk", content)
      end
    end

    class AgentThoughtChunk < ContentUpdate
      def initialize(content)
        super("agent_thought_chunk", content)
      end
    end
  end
end
