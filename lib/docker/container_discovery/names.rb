# frozen_string_literal: true

require 'resolv'
require 'async/dns'

module Docker
  module ContainerDiscovery
    class Names < Async::DNS::Server
      DEFAULT_PORT = 10_053

      def initialize(resolver, metrics, logger, options = {})
        @logger = logger
        @metrics = metrics
        @resolver = resolver

        bind = options[:bind] || '0.0.0.0'
        port = options[:port] || DEFAULT_PORT
        listen = case options[:proto]
                 when :tcp
                   [[:tcp, bind, port]]
                 when :udp
                   [[:udp, bind, port]]
                 else
                   [[:tcp, bind, port], [:udp, bind, port]]
                 end

        super(listen, logger: logger)
      end

      def to_s
        "\#<#{self.class}>"
      end

      def run
        @logger.info(self) { "Starting name server (#{@resolver.zone_master})..." }

        super.run
      end

      def process(name, resource_class, transaction)
        record = resource_class.name.split('::').last
        resolved = case record
                   when 'SOA'
                     process_soa(name, transaction)
                   when 'NS'
                     process_ns(name, transaction)
                   when 'A'
                     process_a(name, transaction)
                   when 'PTR'
                     process_ptr(name, transaction)
                   else
                     false
                   end

        @metrics.receive_query!(record)

        return if resolved

        @metrics.fail_query!(record)
        transaction.fail!(:NXDomain)
      end

      protected

      def process_soa(name, transaction)
        return false unless name == @resolver.tld

        response = @resolver.authority

        transaction.respond!(response.mname,
                             response.rname,
                             response.serial,
                             response.refresh,
                             response.retry,
                             response.expire,
                             response.minimum,
                             ttl: @resolver.res_ttl)
        transaction.append!(transaction.question,
                            Resolv::DNS::Resource::IN::NS,
                            section: :authority)

        true
      end

      def process_ns(name, transaction)
        return false unless name == @resolver.tld

        response = @resolver.zone_master

        transaction.respond!(response, ttl: @resolver.res_ttl)

        true
      end

      def process_a(name, transaction)
        postfix = ".#{@resolver.tld}"

        return false unless name.end_with?(postfix)

        if name == @resolver.zone_master.to_s
          response = @resolver.advertise_addr
          raise 'unable to determine address advertisement' if response.nil?

          @logger.debug(self) { 'Received query for zone nameserver' }
          transaction.respond!(response, ttl: @resolver.res_ttl)
          return true
        end

        ident = name.chomp(postfix)
        result = @resolver.find_address(ident)

        return false if result.empty?

        response = result.map { |a| Resolv::DNS::Resource::IN::A.new(a) }

        @logger.debug(self) { "Query for #{ident} (A) yielded #{result.length} addresses" }
        transaction.append_question!
        transaction.add(response, ttl: @resolver.res_ttl)

        true
      end

      def process_ptr(name, transaction)
        postfix = ".#{Docker::ContainerDiscovery::Resolver::REV_TLD}"

        return false unless name.end_with?(postfix)

        address = @resolver.reverse(name.chomp(postfix))
        result = @resolver.find_ident(address)

        return false if result.nil?

        response = @resolver.name(result)

        @logger.debug(self) { "Query for #{address} (PTR) yielded primary: #{result}" }
        transaction.respond!(response, ttl: @resolver.res_ttl)

        true
      end
    end
  end
end
