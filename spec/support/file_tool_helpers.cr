require "json"

# Shared scaffolding for the specs of the file-based tools (file
# management, text editing, audio editing and image editing).
#
# The tool runners are exercised directly with a `JSON::Any` argument
# built from plain values. Files are created in per-spec temp
# directories within the project root, because the tools only operate
# within the current directory.

module FileToolSpecHelpers
  # Parse a tool's JSON result string into {success, data, error_msg}.
  def parse_run_result(result_json)
    parsed = JSON.parse(result_json)
    hash = parsed.as_h?
    if hash
      err = hash["error"]?
      if err
        return {success: false, data: parsed, error_msg: err.as_s}
      end
    end
    {success: true, data: parsed, error_msg: nil}
  end

  # Build a `JSON::Any` argument object from the given values.
  def make_args(**args) : JSON::Any
    JSON.parse(args.to_json)
  end

  # Read the raw bytes of a file.
  def read_bytes(path)
    File.read(path).bytes
  end

  # Recursively remove a directory, if any.
  def rm_rf_dir(path)
    Dir.each_child(path) do |entry|
      full = File.join(path, entry)
      if Dir.exists?(full)
        rm_rf_dir(full)
      else
        File.delete?(full)
      end
    end
    Dir.delete?(path)
  end
end

# Minimal audio fixtures for the audio tool specs.
module AudioToolSpecFixtures
  # A minimal 44-byte RIFF/WAVE header (PCM, mono, 8 kHz, 16-bit).
  def wav_bytes : String
    "RIFF" +
      "\x24\x00\x00\x00" + # chunk size 36
      "WAVE" +
      "fmt " +
      "\x10\x00\x00\x00" + # fmt chunk size 16
      "\x01\x00" +         # audio format: PCM
      "\x01\x00" +         # channels: 1
      "\x40\x1F\x00\x00" + # sample rate: 8000
      "\x40\x9C\x00\x00" + # byte rate: 40000
      "\x02\x00" +         # block align: 2
      "\x10\x00" +         # bits per sample: 16
      "data" +
      "\x00\x00\x00\x00"   # data size: 0
  end

  # An MP3 file starting with an ID3v2.4 tag.
  def mp3_bytes : String
    "ID3" +
      "\x04\x00\x00" +    # version 2.4, no flags
      "\x00\x00\x00\x00" + # tag size: 0
      "\xFF\xFB\x90\x00"   # MPEG frame sync
  end
end

# Minimal image fixtures for the image tool specs.
module ImageToolSpecFixtures
  # A PNG signature followed by an IHDR chunk (1x1, 8-bit RGB).
  def png_bytes : String
    "\x89PNG\r\n\x1A\n" + # PNG signature
      "\x0D\x00\x00\x00" + # IHDR chunk length: 13
      "IHDR" +
      "\x01\x00\x00\x00" + # width: 1
      "\x01\x00\x00\x00" + # height: 1
      "\x08\x02" +         # 8-bit depth, color type: RGB
      "\x00\x00\x00"       # compression, filter, interlace
  end

  # A JPEG start-of-image marker followed by a JFIF APP0 header.
  def jpeg_bytes : String
    "\xFF\xD8\xFF\xE0" + # SOI + APP0
      "\x0C\x00" +       # segment length: 12 (big-endian)
      "JFIF\x00" +
      "\x01\x01\x00\x01\x00\x01\x00\x00"
  end
end
