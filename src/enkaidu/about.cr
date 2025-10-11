require "./version"

module Enkaidu
  class About
    include JSON::Serializable
    getter app = "Enkaidu"
    getter ver = VERSION

    protected def initialize; end

    # Singleton instance
    def self.me
      @@about ||= About.new
    end
  end
end
