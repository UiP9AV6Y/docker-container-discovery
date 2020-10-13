# frozen_string_literal: true

require 'benchmark'
require 'async/reactor'
require 'async/http/server'
require 'async/http/endpoint'
require 'protocol/http/methods'
require 'protocol/http/response'
require 'protocol/http/body/buffered'

module Docker
  module ContainerDiscovery
    class Web
      DEFAULT_PORT = 19_053
      ROOT_DOCUMENT = <<~HTML
        <html>
        <head><title>Docker Container Discovery</title></head>
        <body>
        <h1>Docker Container Discovery</h1>
        <p><a href="/metrics">Metrics</a></p>
        </body>
        </html>
      HTML
      CONTENT_TYPE_PLAIN = 'text/plain;charset=utf-8'
      CONTENT_TYPE_HTML = 'text/html;charset=utf-8'
      CONTENT_TYPE_JSON = 'application/json;charset=utf-8'

      def initialize(metrics, logger, options = {})
        bind = options[:bind] || '0.0.0.0'
        port = options[:port] || DEFAULT_PORT
        reuse = options[:reuse] || false
        endpoint = Async::HTTP::Endpoint.parse("http://#{bind}:#{port}", reuse_port: reuse)

        @metrics = metrics
        @logger = logger
        @server = Async::HTTP::Server.for(endpoint) do |request|
          trace(request) { respond(request) }
        end
      end

      def to_s
        "\#<#{self.class} #{endpoint_url}>"
      end

      def endpoint_url
        @server.endpoint.to_url
      end

      def run
        @logger.info(self) { 'Starting web server...' }

        Async::Reactor.run(logger: @logger) do |task|
          task.async(logger: @logger) do
            @server.run
          end
        end
      end

      def trace(request)
        response = nil
        path = request.path
        method = request.method.downcase
        duration = Benchmark.realtime { response = yield }

        @metrics.complete_request!(method, path, response.status)
        @metrics.time_request!(method, path, duration)

        response
      rescue StandardError => e
        @metrics.fail_request!(e.class.name)
        @logger.warning(self, e) { "Error while processing request (#{request.method} #{request.path})" }

        Protocol::HTTP::Response.for_exception(e)
      end

      def respond(request)
        @logger.debug(self) { "Recieving web request (#{request.method} #{request.path})" }

        return not_allowed_response unless request.method == Protocol::HTTP::Methods::GET

        case request.path
        when '', '/'
          root_response
        when '/metrics'
          metrics_response
        when '/health'
          health_response
        else
          not_found_response
        end
      end

      def not_allowed_response
        headers = { 'Content-Type' => 'text/plain;charset=utf-8' }
        body = 'Method Not Allowed'

        response(405, headers, body)
      end

      def not_found_response
        headers = { 'Content-Type' => CONTENT_TYPE_PLAIN }
        body = 'Not Found'

        response(404, headers, body)
      end

      def root_response
        headers = { 'Content-Type' => CONTENT_TYPE_HTML }

        response(200, headers, ROOT_DOCUMENT)
      end

      def metrics_response
        headers = { 'Content-Type' => @metrics.content_type }
        body = @metrics.render

        response(200, headers, body)
      end

      def health_response
        headers = { 'Content-Type' => CONTENT_TYPE_JSON }
        body = '{"status": "ok"}'

        response(200, headers, body)
      end

      def response(status, headers, body)
        body = Protocol::HTTP::Body::Buffered.wrap(body)
        headers = Protocol::HTTP::Headers[headers]

        Protocol::HTTP::Response.new(nil, status, headers, body)
      end
    end
  end
end
