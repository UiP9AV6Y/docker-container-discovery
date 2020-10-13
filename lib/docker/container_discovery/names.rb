# frozen_string_literal: true

require 'resolv'
require 'ipaddr'
require 'socket'
require 'async/dns'

module Docker
  module ContainerDiscovery
    class Names < Async::DNS::Server
      DEFAULT_PORT = 10_053

      attr_reader :tld, :refresh, :retry, :expire, :min_ttl

      def initialize(resolver, metrics, logger, options = {})
        @logger = logger
        @metrics = metrics
        @resolver = resolver
        @advertise = options[:advertise]
        @tld = (options[:tld] || 'docker.').chomp(LabelFormatter::LABEL_DELIM)
        @refresh = options[:refresh] || 1200
        @retry = options[:retry] || 900
        @expire = options[:expire] || 3_600_000
        @min_ttl = options[:min_ttl] || 172_800

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

      def serial
        @resolver.last_update.to_time.to_i
      end

      def zone_master
        "ns.#{@tld}"
      end

      def zone_contact
        "hostmaster.#{@tld}"
      end

      def advertise_addr
        @advertise_addr ||= select_address(@advertise)
      end

      protected

      def process_soa(name, transaction)
        return false unless name == @tld

        master = Resolv::DNS::Name.create("#{zone_master}.")
        contact = Resolv::DNS::Name.create("#{zone_contact}.")

        transaction.respond!(master, contact, serial, @refresh, @retry, @expire, @min_ttl)
        transaction.append!(transaction.question, Resolv::DNS::Resource::IN::NS, section: :authority)

        true
      end

      def process_ns(name, transaction)
        return false unless name == @tld

        response = Resolv::DNS::Name.create("#{zone_master}.")

        transaction.respond!(response)

        true
      end

      def process_a(name, transaction)
        postfix = ".#{@tld}"

        return false unless name.end_with?(postfix)

        if name == zone_master
          raise 'unable to determine address advertisement' if advertise_addr.nil?

          @logger.debug(self) { 'Received query for zone nameserver' }
          transaction.respond!(advertise_addr)
          return true
        end

        ident = name.chomp(postfix)
        result = @resolver.find_address(ident)

        return false if result.empty?

        response = result.map { |a| Resolv::DNS::Resource::IN::A.new(a) }

        @logger.debug(self) { "Query for #{ident} (A) yielded #{result.length} addresses" }
        transaction.append_question!
        transaction.add(response)

        true
      end

      def process_ptr(name, transaction)
        postfix = '.in-addr.arpa'

        return false unless name.end_with?(postfix)

        address = name.chomp(postfix).split(LabelFormatter::LABEL_DELIM).reverse.join(LabelFormatter::LABEL_DELIM)
        result = @resolver.find_ident(address)

        return false if result.nil?

        response = Resolv::DNS::Name.create("#{result}.#{@tld}.")

        @logger.debug(self) { "Query for #{address} (PTR) yielded primary: #{result}" }
        transaction.respond!(response)

        true
      end

      def select_address(advertise = nil)
        advertise_candidates = Socket.ip_address_list.map(&:ip_address)

        @resolver.select_address(advertise_candidates, advertise, true)
      end
    end
  end
end
