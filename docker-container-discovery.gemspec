# frozen_string_literal: true

lib = File.join(__dir__, 'lib')
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'docker/container_discovery/version'

Gem::Specification.new do |spec|
  spec.name          = 'docker-container-discovery'
  spec.version       = Docker::ContainerDiscovery::VERSION
  spec.licenses      = ['MIT']
  spec.authors       = ['Gordon Bleux']
  spec.email         = ['UiP9AV6Y+dockercontainerdiscovery@protonmail.com']

  spec.summary       = 'Service discovery for docker containers'
  spec.description   = <<-DESC
  DNS server which provides address resolution for docker containers based
  on their metadata.
  DESC
  spec.homepage = 'https://github.com/uip9av6y/docker-container-discovery'

  if spec.respond_to?(:metadata)
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = "#{spec.homepage}.git"
    spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  end

  spec.bindir        = 'bin'
  spec.require_paths = ['lib']

  Dir.chdir(__dir__) do
    all_dirs        = spec.require_paths + [spec.bindir]
    all_files       = Dir.glob("{#{all_dirs.join(',')}}/**/*")
    test_files      = Dir.glob('{spec}/**/*')

    all_files += %w[LICENSE.txt README.md]
    all_files += [File.basename(__FILE__)]

    spec.files         = all_files
    spec.test_files    = test_files
    spec.executables   = all_files.grep(%r{^bin/}) { |f| File.basename(f) }
  end

  spec.platform              = Gem::Platform::RUBY
  spec.required_ruby_version = '~> 2.3'

  spec.add_development_dependency('bundler', '~> 1.17')
  spec.add_development_dependency('rake', '~> 10.0')
  spec.add_development_dependency('rspec', '~> 3.0')
  spec.add_development_dependency('rubocop', '~> 0.74')

  spec.add_runtime_dependency('async', '~> 1.20', '>= 1.20.1')
  spec.add_runtime_dependency('async-dns', '~> 1.2', '>= 1.2.4')
  spec.add_runtime_dependency('async-http', '~> 0.48', '>= 0.48.2')
  spec.add_runtime_dependency('console', '~> 1.4', '>= 1.4.0')
  spec.add_runtime_dependency('docker-api', '~> 1.34', '>= 1.34.2')
  spec.add_runtime_dependency('prometheus-client', '~> 0.9', '>= 0.9.0')
  spec.add_runtime_dependency('protocol-http', '~> 0.12', '>= 0.12.0')
end
