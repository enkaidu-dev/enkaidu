module FileHelper
  def resolve_path(path)
    File.expand_path(path)
  end

  private def file_exists?(path)
    File.exists?(path)
  end

  def within_current_directory?(requested_path)
    current_dir = File.expand_path(".")
    requested_path.starts_with?(current_dir)
  end

  def valid_file?(resolved_path)
    File.exists?(resolved_path) && File.file?(resolved_path)
  end

  def text_file?(resolved_path)
    begin
      File.open(resolved_path, "r") do |file|
        buffer = uninitialized UInt8[1024]
        bytes_read = file.read_utf8(buffer.to_slice)
        String.new(buffer.to_slice[0, bytes_read], "UTF-8").valid_encoding?
      end
    rescue
      false
    end
  end

  def valid_directory?(requested_path)
    Dir.exists?(requested_path)
  end
end
