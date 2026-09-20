require "socket"
require "uri"

# Decides whether a URL may be fetched.
#
# ```
# policy = FsUtils::Web::HostPolicy.new
# policy.check!(URI.parse("https://example.com/docs"))
# ```
#
# The rule is **resolve, then compare**, which is the sandbox's rule
# applied to a host instead of a path. A name is checked against the
# lists, then looked up, and every address it answers with is checked in
# turn -- a name under the caller's control can point at anything, and
# answering with several addresses of which one is loopback is the usual
# way that is arranged. Checking the string alone would catch nothing.
#
# A redirect is a new URL and gets a new `check!`; the caller is
# responsible for not following one unchecked.
#
# Raises `HostNotAllowedError`, whose suggestion distinguishes the two
# cases a caller can be in: this host is refused, or no host is allowed
# at all and there is no point trying another.
class HostPolicy
  class Error < Exception
    getter suggestion : String?

    def initialize(message : String, @suggestion : String? = nil)
      super(message)
    end

    def code : String?
      nil
    end
  end

  class HostNotAllowedError < Error; end

  class FetchFailedError < Error; end

  # First octet, and the second octets reserved under it. Written out so
  # the set is visible and reviewable rather than deferred to whichever
  # predicates the standard library offers on a given version.
  # `169.254.169.254` is the cloud metadata endpoint, and is the reason
  # this class exists rather than a comment saying to be careful.
  private IPV4_RESERVED = {
    {0, (0..255)},     # this network
    {10, (0..255)},    # private
    {127, (0..255)},   # loopback
    {169, (254..254)}, # link-local
    {172, (16..31)},   # private
    {192, (0..0)},     # IETF protocol assignments
    {192, (168..168)}, # private
    {198, (18..19)},   # benchmarking
    {100, (64..127)},  # carrier-grade NAT
  }

  private IPV6_RESERVED = {"::1", "::"}

  # Unique-local (fc00::/7), link-local (fe80::/10) and multicast.
  private IPV6_RESERVED_PREFIXES = {"fc", "fd", "fe8", "fe9", "fea", "feb", "ff"}

  private IPV4_MAPPED = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i

  class Settings
    # Nil means there is no allowlist. An empty array is an allowlist
    # naming nothing, which permits nothing -- a list means exactly what
    # it contains.
    property allowed_hosts : Array(String)? = nil
    property denied_hosts : Array(String) = [] of String
    property? allow_private_hosts : Bool = false

    def initialize
    end

    def validate! : Nil
      each_pattern do |pattern|
        raise ArgumentError.new("host pattern must not be blank") if pattern.blank?
        raise ArgumentError.new("host pattern #{pattern} must not contain a scheme or path") if pattern.includes?('/')
      end
    end

    # Shallow, so the two arrays are shared by reference: replace one,
    # never mutate it.
    def copy : self
      dup
    end

    private def each_pattern(&)
      @allowed_hosts.try(&.each { |pattern| yield pattern })
      @denied_hosts.each { |pattern| yield pattern }
    end
  end

  # Block form: the settings are yielded for amendment.
  def self.new(&)
    settings = Settings.new
    yield settings
    new(settings)
  end

  def initialize(@settings : Settings = Settings.new)
    @settings.validate!
  end

  # Raises unless every address `uri`'s host resolves to may be reached.
  def check!(uri : URI) : Nil
    host = uri.hostname
    raise HostNotAllowedError.new("the URL names no host", "Send an absolute URL, such as https://example.com/page.") unless host

    check_lists(host)
    check_addresses(host, uri) unless @settings.allow_private_hosts?
  end

  private def check_lists(host : String) : Nil
    if matches?(host, @settings.denied_hosts)
      raise HostNotAllowedError.new(
        "#{host} is not a host this tool may fetch",
        "Fetch a different site, or ask the operator to allow this one.")
    end

    allowed = @settings.allowed_hosts
    return unless allowed
    return if matches?(host, allowed)

    if allowed.empty?
      raise HostNotAllowedError.new(
        "this tool is configured to fetch no hosts at all",
        "Do not retry with another URL; no URL will work. Use a local file, or ask the operator to allow a host.")
    end

    raise HostNotAllowedError.new(
      "#{host} is not one of the hosts this tool may fetch",
      "Fetch one of the allowed sites, or ask the operator to allow this one.")
  end

  # A pattern matches the host exactly, or matches a parent domain of it,
  # so "example.com" covers "docs.example.com" but not "notexample.com".
  private def matches?(host : String, patterns : Array(String)) : Bool
    name = host.downcase.rstrip('.')
    patterns.any? do |pattern|
      candidate = pattern.downcase.lstrip('.').rstrip('.')
      name == candidate || name.ends_with?(".#{candidate}")
    end
  end

  private def check_addresses(host : String, uri : URI) : Nil
    addresses = resolve(host, uri)
    raise FetchFailedError.new("#{host} resolved to no addresses", "Check the hostname's spelling.") if addresses.empty?

    addresses.each do |address|
      next unless private?(address)
      raise HostNotAllowedError.new(
        "#{host} resolves to #{address}, which is on this machine or its private network",
        "Fetch a public URL. Local files are read with read_text_file.")
    end
  end

  private def resolve(host : String, uri : URI) : Array(String)
    port = uri.port || (uri.scheme == "http" ? 80 : 443)
    Socket::Addrinfo.resolve(host, port, type: Socket::Type::STREAM).map(&.ip_address.address)
  rescue ex : Socket::Error
    raise FetchFailedError.new(
      "#{host} could not be resolved: #{ex.message}",
      "Check the hostname's spelling, or try a different site.")
  end

  # True for anything not routable on the public internet.
  private def private?(address : String) : Bool
    if mapped = IPV4_MAPPED.match(address)
      return ipv4_private?(mapped[1])
    end
    address.includes?('.') ? ipv4_private?(address) : ipv6_private?(address)
  end

  private def ipv4_private?(address : String) : Bool
    octets = address.split('.').map(&.to_i?)
    return true unless octets.size == 4
    first, second = octets[0], octets[1]
    return true unless first && second

    return true if first >= 224 # multicast and reserved
    IPV4_RESERVED.any? { |(prefix, range)| first == prefix && range.includes?(second) }
  end

  private def ipv6_private?(address : String) : Bool
    name = address.downcase.split('%').first
    return true if IPV6_RESERVED.includes?(name)
    IPV6_RESERVED_PREFIXES.any? { |prefix| name.starts_with?(prefix) }
  end
end
