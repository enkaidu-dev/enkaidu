require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Config cordon allow_env" do
  context "allow_env parsing" do
    it "parses multiple entries" do
      config = Enkaidu::Config.from_yaml(<<-YAML)
        cordon:
          policy:
            allow_env:
              BOO: HOO
              FOO: BAR
      YAML

      expect(config.cordon.not_nil!.policy.not_nil!.allow_env).to eq({"BOO" => "HOO", "FOO" => "BAR"})
    end

    it "parses and substitutes env var passthrough " do
      config = Enkaidu::Config.from_yaml(<<-YAML)
        cordon:
          policy:
            allow_env:
              MY_PWD: $PWD
      YAML

      expect(config.cordon.not_nil!.policy.not_nil!.allow_env).to eq({"MY_PWD" => Dir.current})
    end

    it "defaults to an empty hash when allow_env is absent" do
      config = Enkaidu::Config.from_yaml(<<-YAML)
        cordon:
          policy:
            allow_network: true
      YAML

      expect(config.cordon.not_nil!.policy.not_nil!.allow_env).to eq({} of String => String)
    end

    it "leaves cordon nil when the cordon section is absent" do
      config = Enkaidu::Config.from_yaml(<<-YAML)
        session:
          system_prompt_name: "greeting"
      YAML

      expect(config.cordon).to be_nil
    end

    it "parses allow_env alongside other policy properties" do
      config = Enkaidu::Config.from_yaml(<<-YAML)
        cordon:
          policy:
            allow_network: true
            read_only_paths:
              - /usr/share/myapp
            allow_env:
              BOO: HOO
      YAML

      policy = config.cordon.not_nil!.policy.not_nil!
      expect(policy.allow_env).to eq({"BOO" => "HOO"})
      expect(policy.allow_network?).to be(true)
      expect(policy.read_only_paths).to eq(["/usr/share/myapp"])
    end
  end
end
