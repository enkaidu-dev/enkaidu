require "../../../spec_helper"
require "json"
require "base64"

Spectator.describe Tools::AudioEditing::ReadAudioFileTool do
  include FileToolSpecHelpers
  include AudioToolSpecFixtures

  let(:temp_dir) { "spec/tmp_read_audio_test" }
  let(:runner)   { Tools::AudioEditing::ReadAudioFileTool::Runner.new }

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

  context "reads a valid wav file" do
    let(:file_path) { File.join(temp_dir, "sample.wav") }

    before { File.write(file_path, wav_bytes) }

    it "returns a reply with a wav audio attachment" do
      reply = expect_reply(runner.execute(make_args(file_path: file_path)))

      expect(reply.content).to contain(file_path)

      expect(reply.has_attachments?).to be_true
      attachment = nil
      reply.each_attachment { |item| attachment = item }
      expect(attachment).to be_a(LLM::Function::Reply::Audio)

      audio = attachment.as(LLM::Function::Reply::Audio)
      expect(audio.format).to eq("wav")
      expect(audio.base64_data).to eq(Base64.strict_encode(wav_bytes))
    end
  end

  context "reads a valid mp3 file with an ID3 tag" do
    let(:file_path) { File.join(temp_dir, "sample.mp3") }

    before { File.write(file_path, mp3_bytes) }

    it "returns a reply with an mp3 audio attachment" do
      reply = expect_reply(runner.execute(make_args(file_path: file_path)))

      expect(reply.content).to contain(file_path)

      expect(reply.has_attachments?).to be_true
      attachment = nil
      reply.each_attachment { |item| attachment = item }
      expect(attachment).to be_a(LLM::Function::Reply::Audio)

      audio = attachment.as(LLM::Function::Reply::Audio)
      expect(audio.format).to eq("mp3")
      expect(audio.base64_data).to eq(Base64.strict_encode(mp3_bytes))
    end
  end

  context "success_response builds a reply with an audio attachment" do
    it "attaches the audio data and downcases the format" do
      reply = runner.success_response("a.wav", Base64.strict_encode(wav_bytes), "WAV")

      expect(reply.content).to eq("Audio read from 'a.wav' will be sent separately.")

      attachment = nil
      reply.each_attachment { |item| attachment = item }
      expect(attachment).to be_a(LLM::Function::Reply::Audio)

      audio = attachment.as(LLM::Function::Reply::Audio)
      expect(audio.format).to eq("wav")
      expect(audio.base64_data).to eq(Base64.strict_encode(wav_bytes))
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
      expect_error(runner.execute(make_args(file_path: File.join(temp_dir, "ghost.wav"))),
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

  context "fails when the file is not an allowed audio format" do
    let(:file_path) { File.join(temp_dir, "notes.txt") }

    before { File.write(file_path, "not audio at all") }

    it "returns an error" do
      expect_error(runner.execute(make_args(file_path: file_path)),
                   /not an allowed audio format/)
    end
  end

  context "fails when the path resolves outside the current directory" do
    let(:outside_path) { File.tempname("_outside.wav") }

    it "returns an error" do
      expect_error(runner.execute(make_args(file_path: outside_path)),
                   /is not allowed/)
    end
  end
end
