# frozen_string_literal: true

require 'time'

module Docker
  module ContainerDiscovery
    class Zone
      def initialize(resolver, logger, options = {})
        @renderer = options[:renderer] || Docker::ContainerDiscovery::ZoneFormats::Bind

        @resolver = resolver
        @logger = logger
      end

      # @return [String]
      def content_type
        @renderer::CONTENT_TYPE
      end

      # @return [Fixnum]
      def max_age
        @resolver.res_ttl
      end

      # @return [Time]
      def last_modified
        @resolver.last_update.to_time
      end

      # @return [Time]
      def expires
        Time.now + @resolver.res_ttl
      end

      # @return [String]
      def render
        @renderer.marshal(@resolver)
      end
    end
  end
end
