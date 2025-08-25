module MCPC
  class TransportTypeException < Exception; end

  enum TransportType
    AutoDetect
    LegacySSE
    ModernHTTP

    def label
      case self
      in .auto_detect? then "auto"
      in .legacy_sse?  then "legacy"
      in .modern_http? then "http"
      end
    end

    def self.from?(label) : TransportType?
      case label
      when "auto"   then AutoDetect
      when "legacy" then LegacySSE
      when "http"   then ModernHTTP
      else
        nil
      end
    end

    def self.from(label) : TransportType
      self.from?(label) || raise TransportTypeException.new("Unknown parameter type label: #{label}")
    end
  end
end
