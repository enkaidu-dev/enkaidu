require "../../../spec_helper"
require "json"
require "base64"
require "uri"

Spectator.describe Tools::ImageEditing::ReadImageFileTool do
  include FileToolSpecHelpers
  include ImageToolSpecFixtures

  let(:temp_dir) { "spec/tmp_read_image_test" }
  let(:runner)   { Tools::ImageEditing::ReadImageFileTool::Runner.new }

  before { Dir.mkdir_p(temp_dir) }
  after { rm_rf_dir(temp_dir) if Dir.exists?(temp_dir) }

  def expect_error(result, pattern)
    expect(result).to be_a(String)
    parsed = parse_run_result(result.as(String))
    expect(parsed[:success]).to be_false
    expect(parsed[:error_msg]).to match(pattern)
  end

  def expect_reply(result)
    expect(result).to be_a(LLM::Function::Reply)
    result.as(LLM::Function::Reply)
  end

  # -------------------------------------------------
  # Successful read scenarios
  # -------------------------------------------------

  context "reads a valid png file" do
    let(:file_path) { File.join(temp_dir, "sample.png") }

    before { File.write(file_path, png_bytes) }

    it "returns a reply with a png data URL attachment" do
      reply = expect_reply(runner.execute(make_args(file_path: file_path)))

      expect(reply.content).to contain(file_path)

      expect(reply.has_attachments?).to be_true
      attachment = nil
      reply.each_attachment { |item| attachment = item }
      expect(attachment).to be_a(LLM::Function::Reply::Image)

      image = attachment.as(LLM::Function::Reply::Image)
      expect(image.image_url.to_s).to eq("data:image/png;base64,#{Base64.strict_encode(png_bytes)}")
    end
  end

  context "reads a valid jpeg file" do
    let(:file_path) { File.join(temp_dir, "sample.jpg") }

    before { File.write(file_path, jpeg_bytes) }

    it "returns a reply with a jpeg data URL attachment" do
      reply = expect_reply(runner.execute(make_args(file_path: file_path)))

      expect(reply.content).to contain(file_path)

      expect(reply.has_attachments?).to be_true
      attachment = nil
      reply.each_attachment { |item| attachment = item }
      expect(attachment).to be_a(LLM::Function::Reply::Image)

      image = attachment.as(LLM::Function::Reply::Image)
      expect(image.image_url.to_s).to eq("data:image/jpeg;base64,#{Base64.strict_encode(jpeg_bytes)}")
    end
  end

  context "success_response builds a reply with an image attachment" do
    let(:data_url) { "data:image/png;base64,QUJD" }

    it "attaches the image data URL" do
      reply = runner.success_response("a.png", data_url)

      expect(reply.content).to eq("Image read from 'a.png' will be sent separately.")

      attachment = nil
      reply.each_attachment { |item| attachment = item }
      expect(attachment).to be_a(LLM::Function::Reply::Image)

      image = attachment.as(LLM::Function::Reply::Image)
      expect(image.image_url).to eq(URI.parse(data_url))
    end
  end

  # -------------------------------------------------
  # Error handling scenarios
  # -------------------------------------------------

  context "fails when file_path is not provided" do
    it "returns an error" do
      expect_error(runner.execute(make_args),
                   /The required file_path was not specified/)
    end
  end

  context "fails when the file does not exist" do
    it "returns an error" do
      expect_error(runner.execute(make_args(file_path: File.join(temp_dir, "ghost.png"))),
                   /does not exist/)
    end
  end

  context "fails when the path is a directory" do
    let(:sub_dir) { File.join(temp_dir, "a_dir") }

    before { Dir.mkdir_p(sub_dir) }

    it "returns an error" do
      expect_error(runner.execute(make_args(file_path: sub_dir)),
                   /does not exist/)
    end
  end

  context "fails when the file is not an image" do
    let(:file_path) { File.join(temp_dir, "notes.txt") }

    before { File.write(file_path, "not an image at all") }

    it "returns an error" do
      expect_error(runner.execute(make_args(file_path: file_path)),
                   /is not an image file/)
    end
  end

  context "fails when the path resolves outside the current directory" do
    let(:outside_path) { File.tempname("_outside.png") }

    it "returns an error" do
      expect_error(runner.execute(make_args(file_path: outside_path)),
                   /is not allowed/)
    end
  end
end
