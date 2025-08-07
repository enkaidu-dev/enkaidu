require "option_parser"
require "markterm"

require "./llm/azure_openai"
require "./llm/ollama"
require "./tools"

provider_name = nil
model_name = nil
debug_on = false
stream_on = false
log_file = nil

def warning(message)
  STDERR.puts "***".colorize(:red)
  STDERR.puts message.colorize(:red)
  STDERR.puts
end

def error_with(message, help = nil)
  STDERR.puts message.colorize(:red)
  if help
    STDERR.puts
    STDERR.puts help
  end
  exit(1)
end

opts = OptionParser.parse do |parser|
  parser.banner = "Usage: #{PROGRAM_NAME} [arguments]\n\nOptions"
  parser.on("-p NAME", "--provider=NAME", "The name of the provider: azure_openai, ollama") { |name| provider_name = name }
  parser.on("-m NAME", "--model=NAME", "Some providers require a model.") { |name| model_name = name }
  parser.on("-L FILEPATH", "--log-file=FILEPATH", "Log chat events to log file (JSON)") do |path|
    log_file = File.open(path, "w")
  rescue ex
    error_with "ERROR: Unable to create log file: #{ex.message}", parser
  end
  parser.on("-D", "--debug", "Enable debug mode") { debug_on = true }
  parser.on("-S", "--streaming", "Enable streaming mode") { stream_on = true }
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
  parser.invalid_option do |flag|
    error_with "ERROR: #{flag} is not a valid option.", parser
  end
end

if provider_name.nil?
  error_with "ERROR: Provider required.", opts
elsif provider_name == "ollama" && model_name.nil?
  error_with "ERROR: Model required by Ollama provider.", opts
end

connection = case provider_name
             when "azure_openai" then LLM::AzureOpenAI::ChatConnection.new
             when "ollama"       then LLM::Ollama::ChatConnection.new
             else
               error_with "ERROR: Unknown provider: #{provider_name}"
             end

chat = connection.new_chat do
  unless (m = model_name).nil?
    with_model m
  end
  with_debug if debug_on
  with_streaming if stream_on
  with_system_message "You are a capable coding assistant with the ability to use tool calling."
  with_tool ListFilesTool
  with_tool ReadTextFileTool
  with_tool CreateTextFileTool
  with_tool ReplaceTextInTextFileTool
  with_tool RenameFileTool
end

macro log(s)
  if (log_io = log_file)
    log_io.puts {{s}} 
  end
end

macro log_close
  if (log_io = log_file)
    log_io.close
  end
end

def process_event(r, chat, tools)
  case r["type"]
  when "tool_call"
    tools << r["content"]
    print "  CALL".colorize(:green)
    puts " #{r["content"].dig("function", "name").as_s.colorize(:red)} with #{r["content"].dig("function", "arguments").colorize(:red)}" unless chat.streaming?
  when "text"
    puts "----".colorize(:green)
    puts Markd.to_term(r["content"].as_s) unless chat.streaming?
  when .starts_with? "error"
    warning("ERROR:\n#{r["content"].to_json}")
  end
end

def ask(chat, log_file, query, render_query = false)
  log "["
  ix = 0
  tools = [] of JSON::Any
  # ask and handle the initial query and its events
  if render_query
    puts "QUERY".colorize(:yellow)
    puts query
  end
  chat.ask query do |r|
    unless r["type"] == "done"
      log "," if ix.positive?
      log r.to_json
      ix += 1
      process_event(r, chat, tools)
    end
  end
  # deal with any tool calls and subsequent events repeatedly until
  # no more tool calls remain
  until tools.empty?
    calls = tools
    tools = [] of JSON::Any
    chat.call_tools_and_ask calls do |r|
      unless r["type"] == "done"
        log "," if ix.positive?
        log r.to_json
        ix += 1
        process_event(r, chat, tools)
      end
    end
  end
  log "]"
end

Q = ["What kind of app or project is in the src/riker folder?"]

# Q = [
#   "Please describe how bubble sort works in no more than 5 steps.",
#   "How does this differ from Quick Sort?",
# ]

if chat.streaming?
  puts "WARNING: No chat output when streaming is enabled (for now). Sorry.".colorize(:yellow)
end

begin
  log "["
  # Q.each_with_index do |q, i|
  #   log "," if i.positive?
  #   ask(chat, log_file, query: q, render_query: true)
  #   puts
  # end
  done = false
  count = 0
  while !done
    print "----\nQUERY > ".colorize(:yellow)
    if (q = gets)
      q = q.chomp
      if q.starts_with? "/"
        case q
        when "/bye" then done = true
        else
          warning("ERROR: Unknown command: #{q}")
        end
      else
        log "," if count.positive?
        ask(chat, log_file, query: q)
        count += 1
        puts
      end
    else
      warning("ERROR: Unexpected end of input IO")
      done = true
    end
  end
  log "]"
ensure
  log_close
end
