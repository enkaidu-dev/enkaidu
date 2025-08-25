# `SensitiveData` is a generic class to handle and encapsulate sensitive data securely.
class SensitiveData(T)
  getter label : String
  private getter value : T

  def initialize(@label, @value); end

  # Returns the sensitive value
  def sensitive_data : T
    value
  end

  # Override to hide the value
  def to_s(io)
    io << "SENSITIVE(" << label << ")"
  end

  # Override to hide the value
  def inspect(io)
    io << "SENSITIVE(label: \"" << label << "\", value: " << T.class.name ")"
  end
end
