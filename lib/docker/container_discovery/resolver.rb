# frozen_string_literal: true

require 'date'

module Docker
  module ContainerDiscovery
    class Resolver
      attr_reader :last_update

      LABEL_NS = 'com.docker.container-discovery/'
      IGNORE_LABEL = "#{LABEL_NS}ignore"
      ADVERTISE_LABEL = "#{LABEL_NS}advertise"
      IDENT_LABEL = "#{LABEL_NS}ident."
      SELECT_EXCLUDES = ['127.0.0.1', '::1'].freeze

      def initialize(formatter, logger, options = {})
        @formatter = formatter
        @logger = logger
        @lock = Mutex.new
        @last_update = Time.at(0).to_datetime
        @container_cidr = options[:container_cidr]

        @ident_address = Docker::ContainerDiscovery::ArrayTree.new
        @address_ident = Hash.new { |hash, key| hash[key] = [] }
      end

      def to_s
        "\#<#{self.class}>"
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
