require "../../../spec_helper"
require "../../../support/enkaidu_session_helpers"

# Keep execution independent of local shell, permissions, and cordon configuration.
class ShellCommandTestFunction < Enkaidu::ShellCommandFunction
  def allowed_commands : Array(String)
    ["test-command"]
  end

  def approved_commands : Array(String)
    ["test-command"]
  end

  def run_with_cordon : CordonHow
    CordonHow::None
  end
end

class ShellCommandTestRunner < Enkaidu::ShellCommandFunction::Runner
  def run_command(cmd)
    {exit_code: 0, stdout: "out", stderr: "err"}
  end
end

Spectator.describe Enkaidu::ShellCommandFunction do
  include LLMSpecHelpers

  it "returns output inline for absent, empty, and whitespace-only prefixes" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      runner = ShellCommandTestRunner.new(ShellCommandTestFunction.new(Enkaidu::Runtime.new(options, renderer)))

      [nil, "", "  \t\n"].each do |prefix|
        args = {"command" => "test-command", "save_as_file_path_prefix" => prefix}
        args.delete("save_as_file_path_prefix") if prefix.nil?
        result = JSON.parse(runner.execute(JSON.parse(args.to_json)))
        expect(result["output"]["stdout"]["content"].as_s).to eq("out")
        expect(result["output"]["stderr"]["content"].as_s).to eq("err")
        expect(result["output"]["stdout_file"]?).to be_nil
      end
    end
  end

  it "saves both streams using underscore suffixes for a non-blank prefix" do
    with_ollama_envs do
      renderer = EnkaiduWiretapTestRenderer.new
      options = EnkaiduWiretapTestOptions.new(renderer, "ollama")
      runner = ShellCommandTestRunner.new(ShellCommandTestFunction.new(Enkaidu::Runtime.new(options, renderer)))
      prefix = "spec/tmp_shell_command_output"
      stdout_path = "#{prefix}_stdout.txt"
      stderr_path = "#{prefix}_stderr.txt"
      begin
        args = {"command" => "test-command", "save_as_file_path_prefix" => prefix, "overwrite" => true}
        result = JSON.parse(runner.execute(JSON.parse(args.to_json)))
        expect(result["output"]["stdout_file"].as_s).to eq(File.expand_path(stdout_path))
        expect(result["output"]["stderr_file"].as_s).to eq(File.expand_path(stderr_path))
        expect(File.read(stdout_path)).to eq("out")
        expect(File.read(stderr_path)).to eq("err")
      ensure
        File.delete?(stdout_path)
        File.delete?(stderr_path)
      end
    end
  end
end
