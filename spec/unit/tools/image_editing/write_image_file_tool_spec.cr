require "../../../spec_helper"
require "json"
require "base64"

Spectator.describe Tools::ImageEditing::WriteImageFileTool do
  include FileToolSpecHelpers
  include ImageToolSpecFixtures

  let(:temp_dir) { "spec/tmp_write_image_test" }
  let(:runner)   { Tools::ImageEditing::WriteImageFileTool::Runner.new }

  let(:png_data_url)  { "data:image/png;base64,#{Base64.strict_encode(png_bytes)}" }
  let(:jpeg_data_url) { "data:image/jpeg;base64,#{Base64.strict_encode(jpeg_bytes)}" }

  before { Dir.mkdir_p(temp_dir) }
  after { rm_rf_dir(temp_dir) if Dir.exists?(temp_dir) }

  # -------------------------------------------------
  # Successful write scenarios
  # -------------------------------------------------

  context "writes a png file from a data URL" do
    let(:file_path) { File.join(temp_dir, "out.png") }

    it "succeeds and decodes the data to the file" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: png_data_url)))

      expect(result[:success]).to be_true
      expect(result[:data].as_h["message"]).to match(/written successfully/)
      expect(read_bytes(file_path).to_a).to eq(png_bytes.bytes.to_a)
    end
  end

  context "writes a jpeg file from a data URL" do
    let(:file_path) { File.join(temp_dir, "out.jpg") }

    it "succeeds and decodes the data to the file" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: jpeg_data_url)))

      expect(result[:success]).to be_true
      expect(result[:data].as_h["message"]).to match(/written successfully/)
      expect(read_bytes(file_path).to_a).to eq(jpeg_bytes.bytes.to_a)
    end
  end

  context "creates a file in a nested sub-directory if needed" do
    let(:nested_path) { File.join(temp_dir, "a", "b", "out.png") }

    it "creates directories and writes the file" do
      result = parse_run_result(runner.execute(make_args(file_path: nested_path, image_data: png_data_url)))

      expect(result[:success]).to be_true
      expect(read_bytes(nested_path).to_a).to eq(png_bytes.bytes.to_a)
    end
  end

  context "overwrites an existing file when overwrite is true" do
    let(:file_path) { File.join(temp_dir, "overwrite_me.png") }

    before { File.write(file_path, "stale bytes") }

    it "succeeds and replaces the old content" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: png_data_url, overwrite: true)))

      expect(result[:success]).to be_true
      expect(read_bytes(file_path).to_a).to eq(png_bytes.bytes.to_a)
    end
  end

  # -------------------------------------------------
  # Error handling scenarios
  # -------------------------------------------------

  context "fails when file_path is not provided" do
    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(image_data: png_data_url)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/The required file_path was not specified/)
    end
  end

  context "fails when image_data is not provided" do
    let(:file_path) { File.join(temp_dir, "no_data.png") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/The required image_data was not specified/)
    end
  end

  context "fails when the file already exists and overwrite is false" do
    let(:file_path) { File.join(temp_dir, "exists.png") }

    before { File.write(file_path, "I am here") }

    it "returns an error without modifying the file when overwrite is false" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: png_data_url, overwrite: false)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/already exists/)
      expect(File.read(file_path)).to eq("I am here")
    end

    it "returns an error without modifying the file when overwrite is omitted" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: png_data_url)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/already exists/)
    end
  end

  context "fails when the declared and detected formats do not match" do
    let(:file_path) { File.join(temp_dir, "mismatch.png") }

    it "returns an error" do
      # Declares jpeg but carries png data.
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: "data:image/jpeg;base64,#{Base64.strict_encode(png_bytes)}")))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/Unsupported or mismatched image format/)
    end
  end

  context "fails when the declared content type is not supported" do
    let(:file_path) { File.join(temp_dir, "unsupported.png") }

    it "returns an error" do
      # A gif data URL; the declared type is not supported.
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: "data:image/gif;base64,QUJD")))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/Unsupported or mismatched image format/)
    end
  end

  context "fails when the image data is not a valid data URL" do
    let(:file_path) { File.join(temp_dir, "bad_url.png") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: "not a data url")))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/not a valid data URL/)
    end
  end

  context "fails when the image data is not valid base64" do
    let(:file_path) { File.join(temp_dir, "bad_b64.png") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, image_data: png_data_url + "!!!!")))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/An error occurred while writing the image file/)
    end
  end

  context "fails when the path resolves outside the current directory" do
    let(:outside_path) { File.tempname("_outside.png") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: outside_path, image_data: png_data_url)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/is not allowed/)
    end
  end
end
