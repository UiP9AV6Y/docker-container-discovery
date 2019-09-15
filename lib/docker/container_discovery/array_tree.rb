# frozen_string_literal: true

module Docker
  module ContainerDiscovery
    class ArrayTree
      DEFAULT_WILDCARD = '*'

      class Node
        attr_reader :key, :value, :children, :wildcard

        def initialize(wildcard = DEFAULT_WILDCARD, key = nil, value = [], children = [])
          @key = key
          @value = value
          @children = children
          @wildcard = wildcard
        end

        def leaf?
          @children.empty?
        end

        def empty?
          @value.empty? && @children.all?(&:empty?)
        end

        def depth
          return 0 if @children.empty?

          @children.map(&:depth).max + 1
        end

        def dig(branch)
          search(branch).map(&:value)
        end

        def remove(value, branch)
          search(branch).map do |child|
            value.map { |v| child.value.delete(v) }.compact
          end
        end

        def set(value, branch)
          expand(branch).map do |child|
            old_value = Array.new(child.value)
            child.value.replace(value)
            old_value
          end
        end

        def append(value, branch)
          expand(branch).map do |child|
            child.value.push(*value)
          end
        end

        def delete(branch)
          return nil if branch.empty?

          key = branch.shift

          if branch.empty?
            values = []
            @children.delete_if do |c|
              if (key == @wildcard) || (key == c.key)
                values << c.value
                true
              end
            end

            return values
          end

          @children.select do |c|
            (key == @wildcard) || (key == c.key)
          end.map do |c|
            c.delete(Array.new(branch))
          end.flatten(1)
        end

        def to_s
          values = @value.length
          children = @children.length

          "<#{self.class}: key=#{@key}, values=#{values}, children=#{children}>"
        end

        protected

        def add_child(key)
          child = Node.new(@wildcard, key)
          @children.push(child).last
        end

        def expand(branch)
          return [self] if branch.empty?

          key = branch.shift

          if key == @wildcard
            @children.map { |c| c.expand(Array.new(branch)) }.flatten
          elsif (child = @children.find { |c| key == c.key })
            child.expand(Array.new(branch))
          else
            add_child(key).expand(Array.new(branch))
          end
        end

        def search(branch)
          return [self] if branch.empty?

          key = branch.shift

          @children.select do |c|
            (key == @wildcard) || (key == c.key)
          end.map do |c|
            c.search(Array.new(branch))
          end.flatten
        end
      end

      def initialize(wildcard = DEFAULT_WILDCARD)
        @root = Node.new(wildcard)
      end

      def empty?
        @root.empty?
      end

      def depth
        @root.depth
      end

      def dig(*branch)
        @root.dig(branch)
      end

      def set(value, *branch)
        @root.set(Array(value), branch)
      end

      def append(value, *branch)
        @root.append(Array(value), branch)
      end

      def remove(value, *branch)
        @root.remove(Array(value), branch)
      end

      def delete(*branch)
        if branch.empty?
          value = @root.value
          @root = Node.new(@root.wildcard)
          return value
        end

        @root.delete(branch)
      end
    end
  end
end
