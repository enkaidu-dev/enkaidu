require "../../spec_helper"
require "../../support/enkaidu_session_helpers"

Spectator.describe "Enkaidu::Config auto_load deprecation" do
  let(renderer) { EnkaiduWiretapTestRenderer.new }

  # Parse YAML into a config and run the production migration
  def parse_and_migrate(yaml : String) : Enkaidu::Config
    config = Enkaidu::Config.from_yaml(yaml)
    config.migrate_auto_load_to_session(renderer)
    config
  end

  context "session properties" do
    it "parse mcp_servers, toolsets and system_prompt_name" do
      config = parse_and_migrate(<<-YAML)
        session:
          mcp_servers: ["alpha", "beta"]
          toolsets:
            - "DateAndTime"
            - name: "Web"
              select: ["http_get"]
          system_prompt_name: "greeting"
      YAML

      session = config.session.not_nil!
      expect(session.mcp_servers).to eq(["alpha", "beta"])
      expect(session.toolsets).to eq(["DateAndTime", {name: "Web", select: ["http_get"]}])
      expect(session.system_prompt_name).to eq("greeting")
      expect(renderer.warnings).to be_empty
    end
  end

  context "deprecation warning" do
    it "renders when auto_load is present" do
      config = parse_and_migrate(<<-YAML)
        auto_load:
          system_prompt_name: "greeting"
      YAML

      expect(renderer.warnings).to contain("The `auto_load` section is deprecated; use `session` instead.")
      expect(config.session.not_nil!.system_prompt_name).to eq("greeting")
    end

    it "renders for an explicitly null auto_load without migrating" do
      # Note: `~` (or `null` / empty) is the YAML null value; `nil` is a plain
      # string in YAML
      config = parse_and_migrate("auto_load: ~")

      expect(renderer.warnings).to contain("The `auto_load` section is deprecated; use `session` instead.")
      expect(config.session).to be_nil
    end

    it "renders for an empty auto_load section" do
      config = parse_and_migrate("auto_load: {}")

      expect(renderer.warnings).to contain("The `auto_load` section is deprecated; use `session` instead.")
      expect(config.session).to be_nil
    end

    it "does not render when auto_load is absent" do
      parse_and_migrate(<<-YAML)
        session:
          system_prompt_name: "greeting"
      YAML

      expect(renderer.warnings).to be_empty
    end

    it "renders only once when migration runs twice" do
      config = parse_and_migrate(<<-YAML)
        auto_load:
          system_prompt_name: "greeting"
      YAML
      config.migrate_auto_load_to_session(renderer)

      expect(renderer.warnings.count { |warning| warning.starts_with?("The `auto_load` section is deprecated") }).to eq(1)
    end
  end

  context "priority" do
    it "migrates auto_load values into session when session properties are absent" do
      config = parse_and_migrate(<<-YAML)
        auto_load:
          mcp_servers: ["alpha"]
          toolsets: ["DateAndTime"]
          system_prompt_name: "legacy"
      YAML

      session = config.session.not_nil!
      expect(session.mcp_servers).to eq(["alpha"])
      expect(session.toolsets).to eq(["DateAndTime"])
      expect(session.system_prompt_name).to eq("legacy")
    end

    it "prefers session values over auto_load with per-property warnings" do
      config = parse_and_migrate(<<-YAML)
        auto_load:
          mcp_servers: ["alpha"]
          toolsets: ["DateAndTime"]
          system_prompt_name: "legacy"
        session:
          mcp_servers: ["beta"]
          system_prompt_name: "modern"
      YAML

      session = config.session.not_nil!
      expect(session.mcp_servers).to eq(["beta"])
      expect(session.system_prompt_name).to eq("modern")
      expect(session.toolsets).to eq(["DateAndTime"])

      expect(renderer.warnings).to contain("The `auto_load` section is deprecated; use `session` instead.")
      expect(renderer.warnings).to contain("The `auto_load.mcp_servers` setting will be ignored because `session.mcp_servers` is set.")
      expect(renderer.warnings).to contain("The `auto_load.system_prompt_name` setting will be ignored because `session.system_prompt_name` is set.")
      expect(renderer.warnings).to_not contain("The `auto_load.toolsets` setting will be ignored")
    end
  end

  context "merge_profile_config" do
    it "migrates profile auto_load into the app session" do
      app = parse_and_migrate(<<-YAML)
        auto_load:
          toolsets: ["app-tools"]
      YAML
      profile = Enkaidu::ProfileConfig.from_yaml(<<-YAML)
        auto_load:
          toolsets: ["profile-tools"]
      YAML
      app.merge_profile_config(profile, renderer)

      # Session merge gives profile settings priority
      expect(app.session.not_nil!.toolsets).to eq(["profile-tools"])
      expect(renderer.warnings.count { |warning| warning.starts_with?("The `auto_load` section is deprecated") }).to eq(2)
    end

    it "ignores profile auto_load when the app config sets an explicitly null auto_load" do
      app = parse_and_migrate("auto_load: ~")
      profile = Enkaidu::ProfileConfig.from_yaml(<<-YAML)
        auto_load:
          toolsets: ["profile-tools"]
      YAML
      app.merge_profile_config(profile, renderer)

      expect(app.session).to be_nil
      expect(renderer.warnings).to contain("Using `auto_load: nil` from app config, IGNORING `auto_load` in profile config.")
    end
  end
end
