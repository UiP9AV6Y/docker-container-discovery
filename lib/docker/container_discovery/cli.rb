# frozen_string_literal: true

require 'prometheus/client'
require 'optparse'
require 'console'
# require 'logger'

module Docker
  module ContainerDiscovery
    class CLI
      LOG_LEVELS = {
        fatal: ::Console::Logger::FATAL,
        error: ::Console::Logger::ERROR,
        warning: ::Console::Logger::WARN,
        info: ::Console::Logger::INFO,
        debug: ::Console::Logger::DEBUG
      }.freeze
      ENV_PREFIX = 'DCD_'

      def initialize(program)
        @label_templates = []
        @resolver_opts = {}
        @client_opts = {}
        @names_opts = {}
        @metrics_opts = {}

        @parser = OptionParser.new do |o|
          decorate_init(o)
          o.banner = "Usage: #{program} [OPT...]"

          o.separator ''
          o.separator 'Docker options:'
          decorate_client(o)

          o.separator ''
          o.separator 'Nameserver options:'
          decorate_names(o)

          o.separator ''
          o.separator 'Metrics options:'
          decorate_metrics(o)

          o.separator ''
          o.separator 'Common options:'
          decorate_common(o)
        end
      end

      def to_s
        @parser.to_s
      end

      def parse!(args = nil, env = nil)
        args ||= ARGV
        env ||= ENV
        tpls = select_domain_templates(env)
        argv = select_env_args(env,
                               'docker-socket',
                               'container-cidr',
                               'tld',
                               'advertise',
                               'refresh',
                               'retry',
                               'expire',
                               'min-ttl',
                               'bind',
                               'port',
                               'proto',
                               'metrics-bind',
                               'metrics-port',
                               'verbosity')

        @parser.parse!(args + argv + tpls)
      end

      def log_formatter
        @log_formatter ||= Docker::ContainerDiscovery::Logger.new
      end

      def log_level
        @log_level ||= LOG_LEVELS[:info]
      end

      def logger
        @logger ||= Console::Logger.new(log_formatter, level: log_level)
      end

      def label_formatter
        @label_formatter ||= Docker::ContainerDiscovery::LabelFormatter.new(*@label_templates)
      end

      def registry
        @registry ||= Docker::ContainerDiscovery::Registry.new(Prometheus::Client.registry, logger)
      end

      def resolver
        @resolver ||= Docker::ContainerDiscovery::Resolver.new(label_formatter, logger, @resolver_opts)
      end

      def client
        @client ||= Docker::ContainerDiscovery::Client.new(resolver, registry, logger, @client_opts)
      end

      def names
        @names ||= Docker::ContainerDiscovery::Names.new(resolver, registry, logger, @names_opts)
      end

      def metrics
        @metrics ||= Docker::ContainerDiscovery::Metrics.new(registry, logger, @metrics_opts)
      end

      private

      def decorate_common(parser)
        parser.on_tail('-h', '--help',
                       'Show this message') do
          puts parser
          exit
        end
        parser.on_tail('-v', '--version',
                       'Show version') do
          puts Docker::ContainerDiscovery::VERSION
          exit
        end
        parser.on_tail('-V', '--verbosity LEVEL', LOG_LEVELS.keys,
                       'Set the output verbosity',
                       '(' + LOG_LEVELS.keys.join(', ') + ')') do |v|
          @log_level = LOG_LEVELS[v]
        end
      end

      def decorate_names(parser)
        parser.on('--tld DOMAIN',
                  'Top level domain/Authority zone') do |v|
          @names_opts[:tld] = v
        end
        parser.on('--advertise ADDRESS', IPAddr,
                  'Advertise address for the server.',
                  'If an address is given with a prefix',
                  '(e.g. 192.168.1.0/24) the available',
                  'interfaces are parsed for a match.') do |v|
          @names_opts[:advertise] = v
        end
        parser.on('--refresh SECONDS', Integer,
                  'Zone refresh interval') do |v|
          raise OptionParser::InvalidArgument, 'Refresh must be a positive number' if v < 1

          @names_opts[:refresh] = v
        end
        parser.on('--retry SECONDS', Integer,
                  'Zone retry interval') do |v|
          raise OptionParser::InvalidArgument, 'Retry must be a positive number' if v < 1

          @names_opts[:retry] = v
        end
        parser.on('--expire SECONDS', Integer,
                  'Zone expiration') do |v|
          raise OptionParser::InvalidArgument, 'Expire must be a positive number' if v < 1

          @names_opts[:expire] = v
        end
        parser.on('--min-ttl SECONDS', Integer,
                  'Zone min TTL') do |v|
          raise OptionParser::InvalidArgument, 'Min TTL must be a positive number' if v < 1

          @names_opts[:min_ttl] = v
        end
        parser.on('--bind ADDRESS', IPAddr,
                  'Address to listen for incoming connections') do |v|
          @names_opts[:bind] = v
        end
        parser.on('--port PORT', Integer,
                  'Port to listen for incoming connections') do |v|
          raise OptionParser::InvalidArgument, 'Port must be a positive number' if v < 1
          raise OptionParser::InvalidArgument, 'Port must be less than 65535' if v > 65_535

          @names_opts[:port] = v
        end
        parser.on('--proto PROTO', %i[tcp udp both],
                  'Protocol to listen for incoming connections',
                  '(tcp, udp, both)') do |v|
          @names_opts[:proto] = v
        end
      end

      def decorate_client(parser)
        parser.on('--domain-template TEMPLATE', Array,
                  'Domain template for container information') do |list|
          @label_templates.push(*list)
        end
        parser.on('--container-cidr ADDRESS', IPAddr,
                  'Select the container address',
                  'using this mask') do |v|
          @resolver_opts[:container_cidr] = v
        end
        parser.on('--docker-socket FILE', IPAddr,
                  'Socket to listen for Docker events') do |v|
          raise OptionParser::InvalidArgument, 'File is not a socket' unless File.socket?(v)

          @client_opts[:socket] = v
        end
      end

      def decorate_metrics(parser)
        parser.on('--metrics-bind ADDRESS', IPAddr,
                  'Address to listen for incoming metric requests') do |v|
          @metrics_opts[:bind] = v
        end
        parser.on('--metrics-port PORT', Integer,
                  'Port to listen for incoming metric requests') do |v|
          raise OptionParser::InvalidArgument, 'Port must be a positive number' if v < 1
          raise OptionParser::InvalidArgument, 'Port must be less than 65535' if v > 65_535

          @metrics_opts[:port] = v
        end
      end

      def decorate_init(parser)
        parser.accept(IPAddr) do |addr|
          begin
            IPAddr.new(addr)
          rescue IPAddr::InvalidAddressError => e
            raise OptionParser::InvalidArgument, e
          end
        end
      end

      def select_domain_templates(hsh)
        argv = []
        needle = ENV_PREFIX + 'DOMAIN_TEMPLATE'

        hsh.each do |key, value|
          next unless key.start_with?(needle)
          next if value.nil? || value.empty?

          argv.push('--domain-template', value)
        end

        argv
      end

      def select_env_args(hsh, *names)
        args = []

        names.map do |n|
          var = ENV_PREFIX + n.upcase.tr('-', '_')
          value = hsh[var]

          if value == 'false'
            args.push('--no-' + n)
          elsif value == 'true'
            args.push('--' + n)
          elsif !value.nil?
            args.push('--' + n, value)
          end
        end

        args
      end
    end
  end
end
