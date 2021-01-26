# frozen_string_literal: true

require 'console'
require 'console/serialized/logger'
require 'console/terminal/logger'
require 'optparse'
require 'pathname'
require 'prometheus/client'

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
      LOG_FORMATS = {
        simple: Docker::ContainerDiscovery::Logger,
        terminal: ::Console::Terminal::Logger,
        structured: ::Console::Serialized::Logger
      }.freeze
      FALSY_VALUES = %w[
        false
        no
        off
        0
      ].freeze
      TRUTHY_VALUES = %w[
        true
        yes
        on
        1
      ].freeze
      ENV_PREFIX = 'DCD_'

      def initialize(program)
        @label_templates = []
        @resolver_opts = {}
        @client_opts = {}
        @names_opts = {}
        @web_opts = {}

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
          o.separator 'Webserver options:'
          decorate_web(o)

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
                               'docker-host',
                               'docker-port',
                               'docker-tls-verify',
                               'docker-tls-cacert',
                               'docker-tls-cert',
                               'docker-tls-key',
                               'connect-retries',
                               'connect-timeout',
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
                               'web-bind',
                               'web-port',
                               'log-format',
                               'log-level',
                               'verbosity')

        @parser.parse!(argv + args + tpls)
      end

      def log_level
        @log_level ||= LOG_LEVELS[:info]
      end

      def log_format_factory
        @log_format_factory ||= LOG_FORMATS[:simple]
      end

      def log_formatter
        @log_formatter ||= log_format_factory.new
      end

      def logger
        @logger ||= Console::Logger.new(log_formatter, level: log_level)
      end

      def label_formatter
        @label_formatter ||= Docker::ContainerDiscovery::LabelFormatter.new(*@label_templates)
      end

      def metrics
        @metrics ||= Docker::ContainerDiscovery::Metrics.new(Prometheus::Client.registry, logger)
      end

      def zone
        @zone ||= Docker::ContainerDiscovery::Zone.new(resolver, logger, @web_opts)
      end

      def resolver
        @resolver ||= Docker::ContainerDiscovery::Resolver.new(label_formatter, logger, @resolver_opts)
      end

      def client
        @client ||= Docker::ContainerDiscovery::Client.new(resolver, metrics, logger, @client_opts)
      end

      def names
        @names ||= Docker::ContainerDiscovery::Names.new(resolver, metrics, logger, @names_opts)
      end

      def web
        @web ||= Docker::ContainerDiscovery::Web.new(zone, metrics, logger, @web_opts)
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
        parser.on_tail('--log-format FORMAT', LOG_FORMATS.keys,
                       'Emit log messaged rendered',
                       'using the given format',
                       "(#{LOG_FORMATS.keys.join(', ')})") do |v|
          @log_format_factory = LOG_FORMATS[v]
        end
        parser.on_tail('-V', '--verbosity LEVEL',
                       '--log-level LEVEL', LOG_LEVELS.keys,
                       'Set the output verbosity',
                       "(#{LOG_LEVELS.keys.join(', ')})") do |v|
          @log_level = LOG_LEVELS[v]
        end
      end

      def decorate_names(parser)
        parser.on('--tld DOMAIN',
                  'Top level domain/Authority zone') do |v|
          @resolver_opts[:tld] = v
        end
        parser.on('--advertise ADDRESS', IPAddr,
                  'Advertise address for the server.',
                  'If an address is given with a prefix',
                  '(e.g. 192.168.1.0/24) the available',
                  'interfaces are parsed for a match.') do |v|
          @resolver_opts[:advertise_address] = v
        end
        parser.on('--refresh SECONDS', Integer,
                  'Zone refresh interval') do |v|
          raise OptionParser::InvalidArgument, 'Refresh must be a positive number' if v < 1

          @resolver_opts[:refresh] = v
        end
        parser.on('--retry SECONDS', Integer,
                  'Zone retry interval') do |v|
          raise OptionParser::InvalidArgument, 'Retry must be a positive number' if v < 1

          @resolver_opts[:retry] = v
        end
        parser.on('--expire SECONDS', Integer,
                  'Zone expiration') do |v|
          raise OptionParser::InvalidArgument, 'Expire must be a positive number' if v < 1

          @resolver_opts[:expire] = v
        end
        parser.on('--min-ttl SECONDS', Integer,
                  'Zone min TTL') do |v|
          raise OptionParser::InvalidArgument, 'Min TTL must be a positive number' if v < 1

          @resolver_opts[:min_ttl] = v
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
        parser.on('--docker-socket FILE', Pathname,
                  'Socket to listen for Docker events') do |v|
          raise OptionParser::InvalidArgument, "Invalid socket: #{v}" unless File.socket?(v)

          @client_opts[:socket] = v
        end
        parser.on('--[no-]docker-tls-verify',
                  'Verify the connection with',
                  'the remote docker server') do |v|
          @client_opts[:tls_verify] = v
        end
        parser.on('--docker-tls-cacert FILE', Pathname,
                  'CA file for the TLS connection',
                  'to the remote docker server') do |v|
          @client_opts[:tls_cacert] = v
        end
        parser.on('--docker-tls-cert FILE', Pathname,
                  'Client cert for the TLS connection',
                  'to the remote docker server') do |v|
          @client_opts[:tls_cert] = v
        end
        parser.on('--docker-tls-key FILE', Pathname,
                  'Client key for the TLS connection',
                  'to the remote docker server') do |v|
          @client_opts[:tls_key] = v
        end
        parser.on('--docker-host HOSTNAME', String,
                  'Host to connect to for Docker events') do |v|
          @client_opts[:host] = v
        end
        parser.on('--docker-port PORT', Integer,
                  'Port to connect to for Docker events') do |v|
          @client_opts[:port] = v
        end
        parser.on('--connect-retries [COUNT]', Integer,
                  'Number of retries to connect to remote docker host') do |v|
          @client_opts[:retries] = v
        end
        parser.on('--connect-timeout SECONDS', Integer,
                  'Seconds to wait between reconnects') do |v|
          @client_opts[:retry_timeout] = v
        end
      end

      def decorate_web(parser)
        parser.on('--web-bind ADDRESS', IPAddr,
                  'Address to listen for incoming http requests') do |v|
          @web_opts[:bind] = v
        end
        parser.on('--web-port PORT', Integer,
                  'Port to listen for incoming http requests') do |v|
          raise OptionParser::InvalidArgument, 'Port must be a positive number' if v < 1
          raise OptionParser::InvalidArgument, 'Port must be less than 65535' if v > 65_535

          @web_opts[:port] = v
        end
      end

      def decorate_init(parser)
        parser.accept(IPAddr) do |addr|
          IPAddr.new(addr)
        rescue IPAddr::InvalidAddressError => e
          raise OptionParser::InvalidArgument, e
        end
        parser.accept(Pathname) do |file|
          raise OptionParser::InvalidArgument, "No such file: #{file}" unless File.exist?(file)

          Pathname.new(file)
        end
      end

      def select_domain_templates(hsh)
        argv = []
        needle = "#{ENV_PREFIX}DOMAIN_TEMPLATE"

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
          value = hsh[var].to_s

          if value.empty? # rubocop:disable Style/GuardClause
            next
          elsif FALSY_VALUES.include?(value.downcase)
            args.push("--no-#{n}")
          elsif TRUTHY_VALUES.include?(value.downcase)
            args.push("--#{n}")
          else
            args.push("--#{n}", value)
          end
        end

        args
      end
    end
  end
end
