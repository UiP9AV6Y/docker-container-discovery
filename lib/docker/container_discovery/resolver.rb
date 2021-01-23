# frozen_string_literal: true

require 'date'
require 'ipaddr'
require 'resolv'
require 'socket'
require 'async/dns'

module Docker
  module ContainerDiscovery
    class Resolver
      attr_reader :last_update,
                  :tld, :res_ttl,
                  :hostname, :address,
                  :refresh, :retry, :expire, :min_ttl

      LABEL_NS = 'com.docker.container-discovery/'
      IGNORE_LABEL = "#{LABEL_NS}ignore"
      ADVERTISE_LABEL = "#{LABEL_NS}advertise"
      IDENT_LABEL = "#{LABEL_NS}ident."
      SELECT_EXCLUDES = ['127.0.0.1', '::1'].freeze
      REV_TLD = 'in-addr.arpa'

      def initialize(formatter, logger, options = {})
        @formatter = formatter
        @logger = logger
        @lock = Mutex.new
        @last_update = Time.at(0).to_datetime
        @container_cidr = options[:container_cidr]
        @hostname = options[:advertise_name] || 'ns'
        @contact = (options[:contact] || 'hostmaster').gsub('.', '\.')
        @address = options[:advertise_address]

        @tld = (options[:tld] || 'docker.').chomp(LabelFormatter::LABEL_DELIM)
        @refresh = options[:refresh] || 1200
        @retry = options[:retry] || 900
        @expire = options[:expire] || 3_600_000
        @min_ttl = options[:min_ttl] || 172_800
        @res_ttl = options[:res_ttl] || Async::DNS::Transaction::DEFAULT_TTL

        @ident_address = Docker::ContainerDiscovery::ArrayTree.new
        @address_ident = Hash.new { |hash, key| hash[key] = [] }
      end

      def to_s
        "\#<#{self.class}>"
      end

      # @return [Resolv::DNS::Resource::SOA]
      def authority
        Resolv::DNS::Resource::SOA.new(zone_master,
                                       zone_contact,
                                       serial,
                                       @refresh,
                                       @retry,
                                       @expire,
                                       @min_ttl)
      end

      # @param name [String]
      # @return [Resolv::DNS::Name]
      def name(name = '')
        labels = [@tld, '']
        labels.unshift(name) unless name.empty?

        Resolv::DNS::Name.create(labels.join(LabelFormatter::LABEL_DELIM))
      end

      # @param addr [IPAddr, String]
      # @return [Resolv::DNS::Name]
      def rev_name(addr)
        name = reverse(addr)
        labels = [name, REV_TLD, '']

        Resolv::DNS::Name.create(labels.join(LabelFormatter::LABEL_DELIM))
      end

      # @return [Fixnum]
      def serial
        @last_update.to_time.to_i
      end

      # @return [Resolv::DNS::Name]
      def zone_master
        @zone_master ||= name(@hostname)
      end

      # @return [Resolv::DNS::Name]
      def zone_contact
        @zone_contact ||= name(@contact)
      end

      # @return [Resolv::DNS::Name, nil]
      # @return [nil] if no advertised address is available
      # @see advertise_addr
      def zone_ptr
        return @zone_ptr unless @zone_ptr.nil?

        addr = advertise_addr
        return nil if addr.nil?

        @zone_ptr = rev_name(addr)
        @zone_ptr
      end

      # @return [Resolv::DNS::Name]
      # @return [nil] if the advertised address is not part of the
      #   address pool.
      def advertise_addr
        return @advertise_addr unless @advertise_addr.nil?

        advertise_candidates = Socket.ip_address_list.map(&:ip_address)
        @advertise_addr = select_address(advertise_candidates, @address, true)
        @advertise_addr
      end

      # @param addr [String]
      # @return [String]
      # @example Reverse an Address
      #   resolver.reverse("127.0.0.24") #=> "24.0.0.127"
      def reverse(addr)
        addr.to_s.split(LabelFormatter::LABEL_DELIM).reverse.join(LabelFormatter::LABEL_DELIM)
      end

      def find_ident(address)
        @lock.synchronize do
          break @address_ident[address].first
        end
      end

      def find_address(ident)
        query = @formatter.split(ident.downcase)

        @lock.synchronize do
          break @ident_address.dig(*query).flatten.uniq
        end
      end

      def add_container(container)
        pk = @formatter.sanitize(container.id)
        info = disect(container.info)
        idents = [pk] + select_idents(info)
        address = info[:address]

        if info[:label][IGNORE_LABEL] == 'true'
          @logger.info(self) { "Found IGNORE label on #{pk}" }
          return
        elsif address.nil?
          @logger.warn(self) { "Unable to determine advertisement address for #{pk}" }
          return
        end

        @lock.synchronize do
          @address_ident[address] = idents

          @logger.info(self) { "registering address (#{address}) with #{pk}" }

          idents.each do |i|
            branch = @formatter.split(i)
            @logger.info(self) { "adding ident (#{i}) for #{pk}" }
            @ident_address.append(address, *branch)
          end

          @last_update = DateTime.now
        end
      end

      def remove_container(container)
        pk = @formatter.sanitize(container.id)

        @lock.synchronize do
          # this entry should only contain a single address
          address = @ident_address.delete(pk).flatten.first

          unless address
            @logger.info(self) { "Ignoring container removal for #{pk}" }
            break false
          end

          @logger.info(self) { "removing address (#{address}) from #{pk}" }

          @address_ident.delete(address).each do |i|
            branch = @formatter.split(i)

            next unless @ident_address.remove(address, *branch)

            @logger.info(self) { "removing ident (#{i}) for #{pk}" }
          end

          @last_update = DateTime.now
        end
      end

      # @param pool [Array]
      # @param cidr [IPAddr, String, nil]
      # @param lazy [Boolean]
      # @return [String]
      def select_address(pool, cidr = nil, lazy = false)
        mask = case cidr
               when IPAddr
                 cidr
               when NilClass
                 IPAddr.new('0.0.0.0/0')
               else
                 IPAddr.new(cidr.to_s)
               end

        return mask.to_s if lazy && mask.prefix == 32

        pool.find do |addr|
          addr && !SELECT_EXCLUDES.include?(addr) && mask.include?(addr)
        end
      end

      protected

      def disect(info)
        labels = info.dig('Config', 'Labels') || info['Labels'] || {}
        address = labels[ADVERTISE_LABEL] || @container_cidr

        {
          container: disect_container(info),
          image: disect_image(info),
          label: labels,
          env: disect_env(info),
          address: disect_address(info, address)
        }
      end

      def disect_container(info)
        hostname = info.dig('Config', 'Hostname')
        names = Array(info['Names']) + Array(info['Name'])

        {
          'name' => names.first,
          'ident' => hostname
        }
      end

      def disect_image(info)
        runner = info.dig('Config', 'Image') || info['Image']
        image_name, image_tag = runner.to_s.split(':', 2)
        name_parts = image_name.split('/')
        image_ident = name_parts.pop.to_s
        image_provider = name_parts.pop.to_s

        {
          'name' => image_name.gsub(/[^a-z0-9]+/, '-'),
          'ident' => image_ident.gsub(/[^a-z0-9]+/, '-'),
          'provider' => image_provider.gsub(/[^a-z0-9]+/, '-'),
          'tag' => image_tag || 'latest'
        }
      end

      def disect_env(info)
        environment = info.dig('Config', 'Env') || []
        variables = {}

        environment.map do |pair|
          key, value = pair.split('=', 2)

          variables[key] = value unless value.nil?
        end

        variables
      end

      def disect_address(info, advertise = nil)
        networks = info.dig('NetworkSettings', 'Networks') || {}
        advertise_pool = [info.dig('NetworkSettings', 'IPAddress')] + networks.map { |_k, v| v['IPAddress'] }

        select_address(advertise_pool, advertise, true)
      end

      def select_idents(data)
        data[:label].map do |l, v|
          next unless l.start_with?(IDENT_LABEL)

          v
        end.compact + @formatter.format(data)
      end
    end
  end
end
