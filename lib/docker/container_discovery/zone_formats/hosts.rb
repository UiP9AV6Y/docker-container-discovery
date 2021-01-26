# frozen_string_literal: true

module Docker
  module ContainerDiscovery
    module ZoneFormats
      module Hosts
        MEDIA_TYPE = 'text/plain'
        CONTENT_TYPE = "#{MEDIA_TYPE};charset=utf-8"

        SEPARATOR = ' '
        DELIMITER = "\n"

        def self.marshal(resolver)
          lines = resolver.name_records.map do |(ident, addr)|
            representation(ident, addr)
          end

          lines.push(nil).join(DELIMITER)
        end

        class << self
          private

          def representation(ident, addr)
            address = addr.address.to_s
            hostname = ident.to_s.chomp(Docker::ContainerDiscovery::LabelFormatter::LABEL_DELIM)

            [address, hostname].join(SEPARATOR)
          end
        end
      end
    end
  end
end
