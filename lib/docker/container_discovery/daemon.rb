# frozen_string_literal: true

module Docker
  module ContainerDiscovery
    class Daemon
      def initialize(clients, names, metrics, logger)
        @clients = Array(clients)
        @metrics = metrics
        @names = names
        @logger = logger
      end

      def spawn
        threads = factory

        Kernel.trap('SIGINT') do
          threads.each(&:exit)
        end

        threads.each(&:join)
      end

      protected

      def factory
        names = Thread.new { @names.run }
        metrics = Thread.new { @metrics.run }
        clients = @clients.map do |client|
          Thread.new { client.run }
        end
        guarded = clients + [names, metrics]
        watchdog = Thread.new do
          loop do
            Kernel.sleep(1)

            next unless (corpse = guarded.find { |thread| !thread.status })

            @logger.info(self) { "Shutting down due to termination of #{corpse.name}" }
            # STONITH
            guarded.each(&:exit)
            Thread.exit
          end
        end

        names.name = 'names'
        metrics.name = 'metrics'
        watchdog.name = 'watchdog'
        clients.each_with_index { |thread, index| thread.name = "client#{index}" }

        guarded << watchdog
      end
    end
  end
end
