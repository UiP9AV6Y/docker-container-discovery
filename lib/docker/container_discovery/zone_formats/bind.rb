# frozen_string_literal: true

require 'resolv'

module Docker
  module ContainerDiscovery
    module ZoneFormats
      module Bind
        MEDIA_TYPE = 'text/dns'
        CONTENT_TYPE = "#{MEDIA_TYPE};charset=utf-8"

        SEPARATOR = "\t"
        DELIMITER = "\n"

        def self.marshal(resolver)
          records = [
            [resolver.tld, resolver.authority],
            [resolver.tld, Resolv::DNS::Resource::IN::NS.new(resolver.zone_master)],
            [resolver.zone_master, Resolv::DNS::Resource::IN::A.new(resolver.address)]
          ] + resolver.name_records
          lines = records.map do |(ident, addr)|
            representation(
              addr,
              ident.to_s.chomp(Docker::ContainerDiscovery::LabelFormatter::LABEL_DELIM) + Docker::ContainerDiscovery::LabelFormatter::LABEL_DELIM,
              resolver.res_ttl
            )
          end

          lines.push(nil).join(DELIMITER)
        end

        class << self
          private

          def representation(record, *prefix)
            data = case record
                   when Resolv::DNS::Resource::SOA
                     [
                       'IN', 'SOA',
                       record.mname,
                       record.rname,
                       record.serial,
                       record.refresh,
                       record.retry,
                       record.expire,
                       record.minimum
                     ]
                   when Resolv::DNS::Resource::IN::A
                     [
                       'IN', 'A',
                       record.address
                     ]
                   when Resolv::DNS::Resource::MX
                     [
                       'IN', 'MX',
                       record.preference,
                       record.exchange
                     ]
                   when Resolv::DNS::Resource::CNAME
                     [
                       'IN', 'CNAME',
                       record.name
                     ]
                   when Resolv::DNS::Resource::NS
                     [
                       'IN', 'NS',
                       record.name
                     ]
                   when Resolv::DNS::Resource::PTR
                     [
                       'IN', 'PTR',
                       record.name
                     ]
                   end

            prefix.concat(data).join(SEPARATOR)
          end
        end
      end
    end
  end
end
