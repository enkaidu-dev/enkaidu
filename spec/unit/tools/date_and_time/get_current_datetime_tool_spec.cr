require "../../../spec_helper"

Spectator.describe Tools::DateAndTime::GetCurrentDatetimeTool do
  let(:runner) { Tools::DateAndTime::GetCurrentDatetimeTool::Runner.new }

  # Helper to parse the JSON result from execute
  def parse_result(result_json)
    JSON.parse(result_json).as_h
  end

  context "when execute is called" do
    it "returns a valid JSON string with expected structure" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      expect(parsed).to be_a(Hash(String, JSON::Any))
      expect(parsed).to have_key("local")
      expect(parsed).to have_key("iso_8601")
    end

    it "local field contains date, time, and tz" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)
      local = parsed["local"].as_h

      expect(local).to have_key("date")
      expect(local).to have_key("time")
      expect(local).to have_key("tz")
    end

    it "iso_8601 field is a non-empty string" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      iso_str = parsed["iso_8601"].as_s
      expect(iso_str).to_not be_empty
    end
  end

  context "when validating ISO 8601 format" do
    it "iso_8601 matches ISO 8601 pattern with timezone offset" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      iso_str = parsed["iso_8601"].as_s
      # ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
      iso_format = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/
      expect(iso_str).to match(iso_format)
    end

    it "local date has correct format" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)
      local = parsed["local"].as_h

      date_str = local["date"].as_s
      # Expect YYYY-MM-DD
      expect(date_str).to match(/^\d{4}-\d{2}-\d{2}$/)
    end

    it "local time has correct format" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)
      local = parsed["local"].as_h

      date_str = local["time"].as_s
      # Expect HH:MM::SS +/-HH:MM
      expect(date_str).to match(/^\d{2}\:\d{2}\:\d{2}( [+-]\d{2}\:\d{2})?$/)
    end
  end

  context "when called multiple times" do
    it "returns different timestamps" do
      args = {} of String => JSON::Any

      result_json1 = runner.execute(JSON.parse(args.to_json))
      parsed1 = parse_result(result_json1)
      time1 = Time.parse(parsed1["iso_8601"].as_s, "%FT%T%:z", Time::Location.local)

      # Small sleep to ensure time difference
      sleep 1.millisecond

      result_json2 = runner.execute(JSON.parse(args.to_json))
      parsed2 = parse_result(result_json2)
      time2 = Time.parse(parsed2["iso_8601"].as_s, "%FT%T%:z", Time::Location.local)

      expect(time2).to be_ge(time1)
    end
  end
end
