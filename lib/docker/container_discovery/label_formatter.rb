# frozen_string_literal: true

module Docker
  module ContainerDiscovery
    class LabelFormatter
      attr_reader :templates

      MAX_LABEL_LENGTH = 63
      MAX_DOMAIN_LENGTH = 253
      LABEL_DELIM = '.'

      def initialize(*templates)
        @templates = templates || []
      end

      def format(data = {})
        @templates.map do |tpl|
          format_template(tpl, data)
        end.compact
      end

      def format_template(tpl, data = {})
        miss = false
        result = tpl.gsub(/\{(\w+)\.([^}]+)\}/) do |_match|
          section = Regexp.last_match(1).to_s.to_sym
          lookup = Regexp.last_match(2)
          replace = data.dig(section, lookup).to_s
          miss ||= replace.empty?

          replace
        end

        return nil if miss

        result = sanitize_labels(result)

        return result unless result.empty?
      end

      def split(str)
        str.to_s.split(LABEL_DELIM)
      end

      def sanitize_labels(str)
        split(str).map do |label|
          l = sanitize(label)

          l unless l.empty?
        end.compact.join(LABEL_DELIM)
      end

      def sanitize(str)
        str.to_s.downcase[0, MAX_LABEL_LENGTH].gsub(/[^a-zA-Z0-9\_\-\.]/, '')
      end
    end
  end
end
