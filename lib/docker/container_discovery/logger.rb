# frozen_string_literal: true

require 'date'

module Docker
  module ContainerDiscovery
    class Logger
      def initialize(io = $stdout)
        @io = io
      end

      # noop to satisfy the contract
      def verbose!(value = true); end

      def call(subject = nil, *arguments, **_options, &_block)
        ts = Time.now.strftime('%FT%R:%S')
        prefix = "[#{ts}] "
        padding = ' ' * prefix.length

        @io.write(prefix)
        @io.write(subject) if subject.is_a?(String)
        @io.write(yield) if block_given?
        @io.write("\n")

        arguments.each { |a| format_argument(@io, a, padding) }
      end

      def format_argument(output, value, padding = '')
        case value
        when Array
          value.each do |v|
            output.write(padding)
            output.write(v.to_s)
            output.write("\n")
          end
        when Hash
          value.each do |k, v|
            output.write(padding)
            output.write(k.to_s)
            output.write('=')
            output.write(v.to_s)
            output.write("\n")
          end
        when Exception
          value.backtrace do |v|
            output.write(padding)
            output.write(v.to_s)
            output.write("\n")
          end
        else
          output.write(padding)
          output.write(value.to_s)
          output.write("\n")
        end
      end
    end
  end
end
