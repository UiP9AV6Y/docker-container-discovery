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
                      'unix://' + options[:socket]
                    elsif options[:endpoint]
                      'tcp://' + options[:endpoint]
                    elsif options[:url]
                      options[:url]
                    else
                      Docker.default_socket_url
                    end

        monkey_patch_docker!(options[:api_version])
      end

      def run
        connection = connect

        return unless connection.is_a?(Docker::Connection)

        Async::Reactor.run(logger: @logger) do |task|
          task.async(logger: @logger) do
            setup(connection)
            schedule(connection)
          end
        end
      end

      protected

      def monkey_patch_docker!(api_version = nil)
        return unless Docker.const_defined?('API_VERSION')
        return if api_version.nil? || api_version == Docker::API_VERSION

        # monkeypatch until 2.x is released
        Docker.redefine_const(:API_VERSION, api_version)
      end

      def connect
        options = {
          read_timeout: 60
        }
        connection = Docker::Connection.new(@endpoint, options)
        info = Docker.version(connection)

        @logger.info(self) { "Docker endpoint #{@endpoint} is #{info['Version']}" }

        connection
      rescue Docker::Error::TimeoutError
        @logger.error(self) { "Timeout reached while attempting to connect to #{@endpoint}" }
      rescue Docker::Error::DockerError
        @logger.error(self) { "Docker API #{@endpoint} is no compatible with #{Docker::API_VERSION}" }
      rescue Excon::Error => e
        @logger.error(self, e) { 'Unable to connect to Docker' }
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
