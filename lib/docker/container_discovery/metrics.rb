# frozen_string_literal: true

require 'async/reactor'
require 'async/http/server'
require 'async/http/endpoint'
require 'protocol/http/response'
require 'protocol/http/body/buffered'

module Docker
  module ContainerDiscovery
    class Metrics
      def initialize(registry, logger, options = {})
        bind = options[:bind] || '0.0.0.0'
        port = options[:port] || '19053'
        reuse = options[:reuse] || false
        endpoint = Async::HTTP::Endpoint.parse("http://#{bind}:#{port}", reuse_port: reuse)

        @logger = logger
        @server = Async::HTTP::Server.for(endpoint) do |_request|
          body = Protocol::HTTP::Body::Buffered.wrap(registry.render)
          headers = { 'Content-Type' => registry.content_type }

          Protocol::HTTP::Response.new(nil, 200, headers, body)
        end
      end

      def run
        Async::Reactor.run(logger: @logger) do |task|
          task.async(logger: @logger) do
            @server.run
          end
        end
      end
    end
  end
end
