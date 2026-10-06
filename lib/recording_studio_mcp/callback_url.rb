# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "uri"

module RecordingStudioMcp
  module CallbackUrl
    BLOCKED_RANGES = [
      IPAddr.new("0.0.0.0/8"),
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("100.64.0.0/10"),
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.0.0.0/24"),
      IPAddr.new("192.0.2.0/24"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("198.18.0.0/15"),
      IPAddr.new("198.51.100.0/24"),
      IPAddr.new("203.0.113.0/24"),
      IPAddr.new("224.0.0.0/4"),
      IPAddr.new("240.0.0.0/4"),
      IPAddr.new("::"),
      IPAddr.new("::1"),
      IPAddr.new("::ffff:0:0/96"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10"),
      IPAddr.new("ff00::/8")
    ].freeze

    Parsed = Data.define(:uri, :addresses)
    Error = Class.new(StandardError) do
      attr_reader :reason

      def initialize(reason, message = reason.to_s)
        @reason = reason
        super(message)
      end
    end

    module_function

    def parse!(url)
      uri = URI.parse(url.to_s)
      raise Error.new(:invalid_url, "callback must be HTTPS") unless uri.is_a?(URI::HTTPS)
      raise Error.new(:invalid_url, "callback must be HTTPS") unless uri.scheme == "https"
      raise Error.new(:invalid_url, "callback host is missing") if uri.host.blank?
      raise Error.new(:invalid_url, "callback must not include credentials") if uri.userinfo.present?
      raise Error.new(:private_address, "callback must not use a private address") if blocked_host?(uri.host)
      raise Error.new(:host_not_allowed, "callback host is not allowed") unless host_allowed?(uri.host)

      uri
    rescue URI::InvalidURIError
      raise Error.new(:invalid_url, "callback is not a valid URL")
    end

    def resolve!(url)
      uri = parse!(url)
      addresses = lookup(uri.host)
      raise Error.new(:dns_failure, "callback host did not resolve") if addresses.empty?

      addresses.each { |address| assert_public!(address) }
      Parsed.new(uri: uri, addresses: addresses)
    end

    def assert_public!(address)
      ip = IPAddr.new(address)
      ip = mapped_ipv4(ip) || ip
      return unless blocked?(ip)

      raise Error.new(:private_address, "callback must not use a private address")
    rescue IPAddr::InvalidAddressError
      raise Error.new(:invalid_url, "callback address is invalid")
    end

    def blocked_host?(host)
      name = host.to_s.downcase
      return true if %w[localhost localhost.localdomain metadata.google.internal].include?(name)
      return true if name.end_with?(".localhost", ".local", ".internal", ".lan")

      false
    end
    private_class_method :blocked_host?

    def host_allowed?(host)
      hook = RecordingStudioMcp.configuration.event_callback_host_allowed
      return true if hook.nil?
      return false unless hook.respond_to?(:call)

      hook.call(host) == true
    end
    private_class_method :host_allowed?

    def lookup(host)
      Resolv.getaddresses(host).uniq
    rescue Resolv::ResolvError, SocketError
      []
    end
    private_class_method :lookup

    def blocked?(ip)
      BLOCKED_RANGES.any? do |range|
        range.include?(ip)
      rescue IPAddr::InvalidAddressError
        false
      end
    end
    private_class_method :blocked?

    def mapped_ipv4(ip)
      return unless ip.ipv6? && ip.ipv4_mapped?

      ip.native
    end
    private_class_method :mapped_ipv4
  end
end
