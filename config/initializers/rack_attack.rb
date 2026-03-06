class Rack::Attack
  BLOCKED_PATHS = %w[
    .env
    .git
    .svn
    wp-admin
    wp-login
    wp-content
    wp-includes
    phpmyadmin
    phpMyAdmin
    xmlrpc.php
    administrator
    cgi-bin
  ].freeze

  BLOCKED_PATH_REGEX = Regexp.union(BLOCKED_PATHS.map { |p| /#{Regexp.escape(p)}/i })

  # Block scanner/probe requests
  blocklist("block_scanners") do |req|
    BLOCKED_PATH_REGEX.match?(req.path)
  end

  # Throttle all requests by IP: 120 req/min
  throttle("req/ip", limit: 120, period: 60) do |req|
    req.ip unless req.path == "/up"
  end

  # Return 403 for blocked requests
  self.blocklisted_responder = ->(env) {
    [ 403, { "content-type" => "text/plain" }, [ "Forbidden" ] ]
  }

  # Return 429 for throttled requests
  self.throttled_responder = ->(env) {
    retry_after = (env["rack.attack.match_data"] || {})[:period]
    [ 429, { "content-type" => "text/plain", "retry-after" => retry_after.to_s }, [ "Rate limit exceeded" ] ]
  }

  # Use CF-Connecting-IP when behind Cloudflare
  class Request < ::Rack::Request
    def ip
      @ip ||= env["HTTP_CF_CONNECTING_IP"] || env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip || super
    end
  end
end
