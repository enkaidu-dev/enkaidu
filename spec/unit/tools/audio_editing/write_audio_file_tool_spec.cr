require "../../../spec_helper"
require "json"
require "base64"

Spectator.describe Tools::AudioEditing::WriteAudioFileTool do
  include FileToolSpecHelpers
  include AudioToolSpecFixtures

  let(:temp_dir) { "spec/tmp_write_audio_test" }
  let(:runner)   { Tools::AudioEditing::WriteAudioFileTool::Runner.new }

  let(:wav_data) { Base64.strict_encode(wav_bytes) }

  before { Dir.mkdir_p(temp_dir) }
  after { rm_rf_dir(temp_dir) if Dir.exists?(temp_dir) }

  # -------------------------------------------------
  # Successful write scenarios
  # -------------------------------------------------

  context "writes a wav file from base64 audio data" do
    let(:file_path) { File.join(temp_dir, "out.wav") }

    it "succeeds and decodes the data to the file" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, audio_data: wav_data)))

      expect(result[:success]).to be_true
      expect(result[:data].as_h["message"]).to match(/written successfully/)
      expect(read_bytes(file_path).to_a).to eq(wav_bytes.bytes.to_a)
    end
  end

  context "writes an mp3 file from base64 audio data" do
    let(:file_path) { File.join(temp_dir, "out.mp3") }

    it "succeeds and decodes the data to the file" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, audio_data: Base64.strict_encode(mp3_bytes))))

      expect(result[:success]).to be_true
      expect(result[:data].as_h["message"]).to match(/written successfully/)
      expect(read_bytes(file_path).to_a).to eq(mp3_bytes.bytes.to_a)
    end
  end

  context "creates a file in a nested sub-directory if needed" do
    let(:nested_path) { File.join(temp_dir, "a", "b", "out.wav") }

    it "creates directories and writes the file" do
      result = parse_run_result(runner.execute(make_args(file_path: nested_path, audio_data: wav_data)))

      expect(result[:success]).to be_true
      expect(read_bytes(nested_path).to_a).to eq(wav_bytes.bytes.to_a)
    end
  end

  context "overwrites an existing file when overwrite is true" do
    let(:file_path) { File.join(temp_dir, "overwrite_me.wav") }

    before { File.write(file_path, "stale bytes") }

    it "succeeds and replaces the old content" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, audio_data: wav_data, overwrite: true)))

      expect(result[:success]).to be_true
      expect(read_bytes(file_path).to_a).to eq(wav_bytes.bytes.to_a)
    end
  end

  # -------------------------------------------------
  # Error handling scenarios
  # -------------------------------------------------

  context "fails when file_path is not provided" do
    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(audio_data: wav_data)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/The required file_path was not specified/)
    end
  end

  context "fails when audio_data is not provided" do
    let(:file_path) { File.join(temp_dir, "no_data.wav") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/The required audio_data was not specified/)
    end
  end

  context "fails when the file already exists and overwrite is false" do
    let(:file_path) { File.join(temp_dir, "exists.wav") }

    before { File.write(file_path, "I am here") }

    it "returns an error without modifying the file when overwrite is false" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, audio_data: wav_data, overwrite: false)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/already exists/)
      expect(File.read(file_path)).to eq("I am here")
    end

    it "returns an error without modifying the file when overwrite is omitted" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, audio_data: wav_data)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/already exists/)
    end
  end

  context "fails when the audio data is not an allowed audio format" do
    let(:file_path) { File.join(temp_dir, "bogus.wav") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, audio_data: Base64.strict_encode("not audio"))))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/Unknown audio format/)
    end
  end

  context "fails when the audio data is not valid base64" do
    let(:file_path) { File.join(temp_dir, "bad_b64.wav") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: file_path, audio_data: wav_data + "!!!!")))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/An error occurred while creating/)
    end
  end

  context "fails when the path resolves outside the current directory" do
    let(:outside_path) { File.tempname("_outside.wav") }

    it "returns an error" do
      result = parse_run_result(runner.execute(make_args(file_path: outside_path, audio_data: wav_data)))

      expect(result[:success]).to be_false
      expect(result[:error_msg]).to match(/is not allowed/)
    end
  end
end
