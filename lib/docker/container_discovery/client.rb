# frozen_string_literal: true

require 'async/reactor'
require 'docker'

module Docker
  module ContainerDiscovery
    class Client
      def initialize(resolver, registry, logger, options = {})
        @logger = logger
        @registry = registry
        @resolver = resolver
        @endpoint = if options[:socket]
                      "unix://#{options[:socket]}"
                    elsif options[:endpoint]
                      "tcp://#{options[:endpoint]}"
                    elsif options[:host]
                      port = options[:port] || 2375
                      "tcp://#{options[:host]}:#{port}"
                    elsif options[:url]
                      options[:url]
                    else
                      Docker.default_socket_url
                    end
        @retries = options[:retries] || 0
        @timeout = options[:retry_timeout] || 5
        @connection_options = {
          read_timeout: 60,
          client_cert: options[:client_cert],
          client_key: options[:client_key],
          ssl_ca_file: options[:ssl_ca_file],
          scheme: options[:scheme],
        }.delete_if { |k, v| v.nil? }
      end

      def run
        connection = retry_connect

        return unless validate_connection(connection)

        Async::Reactor.run(logger: @logger) do |task|
          task.async(logger: @logger) do
            setup(connection)
            schedule(connection)
          end
        end
      end

      protected

      def validate_connection(connection)
        case connection
        when Docker::Connection
          return true
        when Docker::Error::TimeoutError
          @logger.error(self) { "Timeout reached while attempting to connect to #{@endpoint}" }
        when Docker::Error::DockerError
          @logger.error(self, connection) { "Docker API @#{@endpoint} did not respond properly" }
        when Excon::Error
          @logger.error(self, connection) { "Unable to connect to #{@endpoint}" }
        else
          @logger.error(self, connection) { "Unexpected error while connecting to #{@endpoint}" }
        end

        false
      end

      def retry_connect
        connection = nil
        attempts = @retries.next

        attempts.times do |a|
          connection = connect

          return connection if connection.is_a?(Docker::Connection)

          if a == @retries
            @logger.info(self, connection) { "Connection attempt (#{a.next}) to #{@endpoint} failed" }
          else
            @logger.info(self, connection) { "Connection attempt (#{a.next}) to #{@endpoint} failed; retry in #{@timeout}s" }
            Kernel.sleep(@timeout)
          end
        end

        connection
      end

      def connect
        connection = Docker::Connection.new(@endpoint, @connection_options)
        info = Docker.version(connection)

        @logger.info(self) { "Docker endpoint #{@endpoint} is #{info['Version']}" }

        connection
      rescue StandardError => e
        e
      end

      def setup(connection)
        Docker::Container.all({}, connection).each do |container|
          @registry.add_container!(@endpoint)
          @resolver.add_container(container)
        end
      rescue Docker::Error::DockerError, Excon::Error => e
        @logger.warn(self, e) { 'Unable to retrieve running containers' }
      end

      def schedule(connection)
        query = {
          type: 'container'
        }
        begin
          Docker::Event.stream(query, connection) do |event|
            cid = event.Actor.ID

            begin
              case event.Action
              when 'die'
                @logger.debug(self) { "Got \"#{event.Action}\" docker event for #{cid}" }
                container = Docker::Container.get(cid, {}, connection)
                @registry.remove_container!(@endpoint)
                @resolver.remove_container(container)
              when 'start'
                @logger.debug(self) { "Got \"#{event.Action}\" docker event for #{cid}" }
                container = Docker::Container.get(cid, {}, connection)
                @registry.add_container!(@endpoint)
                @resolver.add_container(container)
              else
                @logger.debug(self) { "Ignoring docker event for #{cid}: #{event.Action}" }
              end
            rescue Docker::Error::DockerError, Excon::Error => e
              @logger.warn(self, e) { 'Unable to process docker container' }
            end
          end
        rescue Docker::Error::TimeoutError
          @logger.debug(self) { 'Event stream interrupted; reconnecting' }
          retry
        rescue Docker::Error::DockerError => e
          @logger.warn(self, e) { 'Event stream interrupted' }
          retry
        rescue StandardError => e
          @logger.error(self, e) { 'Docker event stream error' }
        end
      end
    end
  end
end
