# frozen_string_literal: true

module Docker
  module ContainerDiscovery
    class Daemon
      def initialize(clients, names, web, logger)
        @clients = Array(clients)
        @web = web
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
        web = Thread.new { @web.run }
        clients = @clients.map do |client|
          Thread.new { client.run }
        end
        guarded = clients + [names, web]
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
        web.name = 'web'
        watchdog.name = 'watchdog'
        clients.each_with_index { |thread, index| thread.name = "client#{index}" }

        guarded << watchdog
      end
    end
  end
end
