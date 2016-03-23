#! /usr/bin/env ruby
#
#   pingmeback-metrics
#
# DESCRIPTION:
#   Get pingmeback metrics
#   https://github.com/yanc0/sensu-plugins-pingmeback
#
# OUTPUT:
#   metric data
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: uri
#   gem: socket
#   gem: oj
#
# USAGE:
#
# NOTES:
#
# LICENSE:
#   Copyright 2016 Yann Coleu
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/metric/cli'
require 'net/http'
require 'net/https'
require 'json'
require 'uri'

#
# Pingmeback Metrics
#
class PingmebackMetrics < Sensu::Plugin::Metric::CLI::Graphite
  option :host,
         short: '-h HOST',
         long: '--host HOST',
         description: 'Your Pingmeback instance',
         required: true,
         default: 'http://localhost/check'

  option :url,
         short: '-u URL',
         long: '--url URL',
         description: 'Your endpoint you want to check',
         required: true

  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.pingmeback"

  def json_valid?(str)
    JSON.parse(str)
    return true
  rescue JSON::ParserError
    return false
  end

  def run
    begin
      uri = URI(config[:host])
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      req.body = { url: config[:url], pattern: config[:pattern] }.to_json
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end

    rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, Net::HTTPBadResponse,
           Net::HTTPHeaderSyntaxError, Net::ProtocolError, Errno::ECONNREFUSED => e
      unknown e
    end

    if json_valid?(res.body)
      json = JSON.parse(res.body)
      json.keys.each do |k|
        if k.to_s == 'http_request_time'
          output "#{config[:scheme]}.http_request_time", json['http_request_time']
        elsif k.to_s == 'message'
          critical json['message']
        end
      end
    else
      unknown 'invalid JSON'
    end
    ok
  end
end
