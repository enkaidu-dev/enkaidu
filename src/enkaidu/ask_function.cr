require "colorize"

module Enkaidu
  # Defines a tool / function to make a single query to Enkaidu
  class AskEnkaiduFunction < LLM::LocalFunction
    name "ask_enkaidu"

    description <<-DESC
    Send Enkaidu a query / prompt to execute, as if the user typed this at the Enkaidu prompt.
    This can include slash (/) commands, macro calls (!) as well as plain text prompts. This
    function returns immediately after scheduling the query.
    DESC

    param "query", type: Param::Type::Str, required: true,
      description: "The query (slash commands, macro calls, or plain text prompts) to Enkaidu"

    # Accessible to the function's Runner
    protected getter session : Session

    def initialize(@session)
      super("Session Built-ins")
    end

    # This defines the runner that is instantiated to
    # execute the function.
    class Runner < LLM::Function::Runner
      private getter func : AskEnkaiduFunction

      def initialize(@func); end

      # Implement this method to handle the LLM function call, and return a
      # String with the JSON value.
      def execute(args : JSON::Any) : String
        query = args["query"]?.try(&.as_s?) || return error_response("Required `query` was not specified")
        query = query.strip
        return error_response("Required `query` was empty") if query.empty?

        func.session.queue_query(query)
        success_response
      rescue ex
        error_response(ex.message)
      end

      # Create a success response as a JSON string
      private def success_response
        {status: "Query queued. Don't wait for response, just stop so the query can executed by the app."}.to_json
      end

      # Create an error response as a JSON string
      private def error_response(message)
        {error: message}.to_json
      end
    end

    # Return an instance of this function's Runner
    def new_runner : Runner
      Runner.new(self)
    end
  end
end
