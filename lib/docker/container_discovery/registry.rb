# frozen_string_literal: true

require 'prometheus/client/formats/text'

module Docker
  module ContainerDiscovery
    class Registry
      def initialize(storage, logger, options = {})
        @logger = logger
        @storage = storage
        @renderer = options[:renderer] || Prometheus::Client::Formats::Text

        prefix = options[:metrics_prefix] || 'dcd'

        init_names_metrics(prefix)
        init_web_metrics(prefix)
        init_container_metrics(prefix)
      end

      def content_type
        @renderer::MEDIA_TYPE
      end

      def fail_query!(in_class)
        @failures.increment(labels: { record: in_class })
      end

      def receive_query!(in_class)
        @queries.increment(labels: { record: in_class })
      end

      def complete_request!(method, path, code)
        labels = {
          method: method,
          path: path,
          code: code
        }

        @requests.increment(labels: labels)
      end

      def time_request!(method, path, duration)
        labels = {
          method: method,
          path: path
        }

        @durations.observe(duration, labels: labels)
      end

      def fail_request!(exception_class)
        @exceptions.increment(labels: { exception: exception_class })
      end

      def add_container!(endpoint)
        @containers.increment(labels: { endpoint: endpoint })
      end

      def remove_container!(endpoint)
        @containers.decrement(labels: { endpoint: endpoint })
      end

      def render
        @renderer.marshal(@storage)
      end

      protected

      def init_names_metrics(metrics_prefix)
        @queries = @storage.counter(
          :"#{metrics_prefix}_queries_total",
          docstring: 'DNS queries received',
          labels: %i[record]
        )
        @failures = @storage.counter(
          :"#{metrics_prefix}_queries_failed",
          docstring: 'DNS queries which yielded NXDOMAIN',
          labels: %i[record]
        )
      end

      def init_web_metrics(metrics_prefix)
        @requests = @storage.counter(
          :"#{metrics_prefix}_requests_total",
          docstring: 'The total number of HTTP requests handled by the web server.',
          labels: %i[method path code]
        )
        @durations = @storage.histogram(
          :"#{metrics_prefix}_request_duration_seconds",
          docstring: 'The HTTP response duration of the web server.',
          labels: %i[method path]
        )
        @exceptions = @storage.counter(
          :"#{metrics_prefix}_exceptions_total",
          docstring: 'The total number of exceptions raised by the web server.',
          labels: [:exception]
        )
      end

      def init_container_metrics(metrics_prefix)
        @containers = @storage.gauge(
          :"#{metrics_prefix}_containers",
          docstring: 'Discovered containers',
          labels: %i[endpoint]
        )
      end
    end
  end
end
