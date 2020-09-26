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
        @queries = storage.counter(
          :"#{prefix}_queries_total",
          docstring: 'DNS queries received',
          labels: [:record]
        )
        @failures = storage.counter(
          :"#{prefix}_queries_failed",
          docstring: 'DNS queries which yielded NXDOMAIN',
          labels: [:record]
        )
        @containers = storage.gauge(
          :"#{prefix}_containers",
          docstring: 'Discovered containers',
          labels: [:endpoint]
        )
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

      def add_container!(endpoint)
        @containers.increment(labels: { endpoint: endpoint })
      end

      def remove_container!(endpoint)
        @containers.decrement(labels: { endpoint: endpoint })
      end

      def render
        @renderer.marshal(@storage)
      end
    end
  end
end
