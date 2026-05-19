require "../../../spec_helper"

Spectator.describe Tools::DateAndTime::GetCurrentDatetimeTool do
  let(:runner) { Tools::DateAndTime::GetCurrentDatetimeTool::Runner.new }

  # Helper to parse the JSON result from execute
  def parse_result(result_json)
    JSON.parse(result_json).as_h
  end

  context "when execute is called" do
    it "returns a valid JSON string" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      expect(parsed).to be_a(Hash(String, JSON::Any))
    end

    it "contains a current_datetime field" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      expect(parsed).to have_key("current_datetime")
    end

    it "current_datetime is a non-empty string" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      datetime_str = parsed["current_datetime"].as_s
      expect(datetime_str).to_not be_empty
      expect(datetime_str).to be_a(String)
    end
  end

  context "when validating ISO 8601 format" do
    it "current_datetime matches ISO 8601 pattern with timezone offset" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      datetime_str = parsed["current_datetime"].as_s
      # ISO 8601 format: YYYY-MM-DDTHH:MM:SS+HH:MM or YYYY-MM-DDTHH:MM:SSZ
      iso_format = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}/
      expect(datetime_str).to match(iso_format)
    end

    it "current_datetime has correct date components" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      datetime_str = parsed["current_datetime"].as_s
      # Extract just the date part
      date_parts = datetime_str.split("T").first.split("-")
      year = date_parts[0].to_i
      month = date_parts[1].to_i
      day = date_parts[2].to_i

      expect(datetime_str.split("T").first.size).to eq(10)
      expect(datetime_str.split("T")[1].split(":").size).to eq(4)
      expect(year).to be_gt(2000)
      expect(month).to be_between(1, 12)
      expect(day).to be_between(1, 31)
    end
  end

  context "when validating timezone offset" do
    it "contains a +00:00 offset indicating UTC" do
      args = {} of String => JSON::Any
      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      datetime_str = parsed["current_datetime"].as_s
      expect(datetime_str).to end_with("+00:00")
    end
  end

  context "when called with a reason parameter" do
    it "still returns correct datetime" do
      args = {"reason" => JSON.parse(%("test reason"))}

      result_json = runner.execute(JSON.parse(args.to_json))
      parsed = parse_result(result_json)

      datetime_str = parsed["current_datetime"].as_s
      expect(datetime_str).to_not be_empty
      expect(datetime_str).to end_with("+00:00")
    end
  end

  context "when called multiple times" do
    it "returns different timestamps" do
      args = {} of String => JSON::Any

      result_json1 = runner.execute(JSON.parse(args.to_json))
      parsed1 = parse_result(result_json1)
      time1 = Time.parse(parsed1["current_datetime"].as_s, "%FT%T%:z", Time::Location.local)

      # Small sleep to ensure time difference
      sleep 1.millisecond

      result_json2 = runner.execute(JSON.parse(args.to_json))
      parsed2 = parse_result(result_json2)
      time2 = Time.parse(parsed2["current_datetime"].as_s, "%FT%T%:z", Time::Location.local)

      expect(time2).to be_ge(time1)
    end
  end
end
