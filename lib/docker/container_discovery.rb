# frozen_string_literal: true

require 'docker/container_discovery/version'

module Docker
  module ContainerDiscovery
    class Error < StandardError; end
  end
end

# monkeypatch plumbing for docker-api gem
class Module
  def redefine_const(name, value)
    __send__(:remove_const, name) if const_defined?(name)
    const_set(name, value)
  end
end

require 'docker/container_discovery/logger'
require 'docker/container_discovery/client'
require 'docker/container_discovery/names'
require 'docker/container_discovery/web'
require 'docker/container_discovery/cli'
require 'docker/container_discovery/zone'
require 'docker/container_discovery/daemon'
require 'docker/container_discovery/resolver'
require 'docker/container_discovery/metrics'
require 'docker/container_discovery/array_tree'
require 'docker/container_discovery/label_formatter'
require 'docker/container_discovery/zone_formats/bind'
require 'docker/container_discovery/zone_formats/hosts'
