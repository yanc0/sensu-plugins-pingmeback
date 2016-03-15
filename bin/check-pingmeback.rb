#! /usr/bin/env ruby
#
#   pingmeback
#
# DESCRIPTION:
#   Check HTTP health via a pingmeback instance
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: json
#   gem: uri
#
# USAGE:
#  #YELLOW
#
# NOTES:
#
# LICENSE:
#   Copyright 2016 Yann Coleu <y@nn-col.eu>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'net/http'
require 'net/https'
require 'json'
require 'uri'
require 'time'

class PingmebackCheck < Sensu::Plugin::Check::CLI
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

  option :pattern,
         short: '-p PATTERN',
         long: '--pattern PATTERN',
         description: 'The string the body must contains',
         required: false,
         default: ''

  option :response_code,
         short: '-r CODE',
         long: '--response_code CODE',
         description: 'The expected response code',
         required: false,
         default: '200'

  option :expiry,
         short: '-e EXPIRY',
         long: '--expiry EXPIRY',
         description: 'Warn if cert expires within days',
         required: false,
         default: '30'

  option :warning_time,
         short: '-w WARNING',
         long: '--warning WARNING',
         description: 'Warn when request time is greater than time ms',
         required: false,
         default: '1000'

  option :critical_time,
         short: '-c CRITICAL',
         long: '--critical CRITICAL',
         description: 'Critical when request time is greater than time ms',
         required: false,
         default: '5000'

  def json_valid?(str)
    JSON.parse(str)
    return true
  rescue JSON::ParserError
    return false
  end

  def run
    begin
      uri = URI(config[:host])
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = { url: config[:url], pattern: config[:pattern] }.to_json
      res = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end

    rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, Net::HTTPBadResponse,
           Net::HTTPHeaderSyntaxError, Net::ProtocolError, Errno::ECONNREFUSED => e
      unknown e
    end

    if json_valid?(res.body)
      json = JSON.parse(res.body)
      json.keys.each do |k|
        if k.to_s == 'http_status_code'
          if json['http_status_code'].to_s != config[:response_code]
            critical "Bad status code response: #{json['http_status_code']}"
          end
        elsif k.to_s == 'ssl_expiry_date' && json[:ssl]
          expires = ((Time.parse(json['ssl_expiry_date']) - Time.now).to_i / (24 * 60 * 60))
          warning "Cert expires in #{expires} days" if expires <= config[:expiry].to_i
        elsif k.to_s == 'http_request_time'
          if json['http_request_time'] > config[:critical_time].to_i
            critical "Request time too long: #{json['http_request_time']}ms"
          elsif json['http_request_time'] > config[:warning_time].to_i
            warning "Request time too long: #{json['http_request_time']}ms"
          end
        elsif k.to_s == 'http_body_pattern'
          unless json['http_body_pattern']
            critical "Pattern \"#{config[:pattern]}\" not present in response body"
          end
        elsif k.to_s == 'message'
          unknown json['message']
        end
      end
    else
      unknown 'invalid JSON'
    end

    ok
  end
end
