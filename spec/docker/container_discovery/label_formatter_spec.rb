# frozen_string_literal: true

RSpec.describe Docker::ContainerDiscovery::LabelFormatter do
  describe '#sanitize' do
    long_input = 'a' * 64
    long_output = 'a' * 63

    {
      'test' => nil,
      'rspec.test' => nil,
      'rspec_test' => nil,
      'rspec-test' => nil,
      'rspec/test' => 'rspectest',
      '/test' => 'test',
      'Rspec' => 'rspec',
      long_input => long_output
    }.each do |input, output|
      it("sanitizes '#{input}' correctly") { expect(subject.sanitize(input)).to eq(output || input) }
    end
  end

  describe '#format' do
    let(:data) do
      {
        rspec: {
          'null' => nil,
          'empty' => '',
          'test' => 'test',
          'multi.test' => 'multi-test',
          'com.example/debug' => 'true',
          'long' => 'x' * 70
        },
        case: {
          'UPPER' => 'uppercase',
          'Mixed' => 'mixed case'
        }
      }
    end

    long_label = 'a' * 64

    {
      'static' => 'static',
      'multiple.static' => 'multiple.static',
      '{rspec}' => 'rspec', # pattern mismatch
      '{rspec.nonexistent}' => nil,
      '{rspec.null}' => nil,
      '{rspec.empty}' => nil,
      '{rspec.empty}.{rspec.null}' => nil,
      '{rspec.test}' => 'test',
      '{rspec.multi.test}' => 'multi-test',
      '{rspec.com.example/debug}.rspec' => 'true.rspec',
      '{rspec.test}-{rspec.multi.test}' => 'test-multi-test',
      '[invalid]' => 'invalid',
      '' => nil,
      '.' => nil,
      '{rspec.nonexistent}.{rspec.nonexistent}' => nil,
      '{rspec.nonexistent}-{rspec.nonexistent}' => nil,
      '{case.UPPER}' => 'uppercase',
      '{case.Mixed}' => 'mixedcase',
      '{rspec.long}' => 'x' * 63,
      long_label => 'a' * 63
    }.each do |input, output|
      context "using #{input}" do
        subject do
          described_class.new(input)
        end

        it do
          expect(subject.format(data).first).to eq(output)
        end
      end
    end
  end

  describe '#sanitize_labels' do
    {
      'rspec.test' => 'rspec.test',
      'RSPEC.TEST' => 'rspec.test',
      'rspec..test' => 'rspec.test',
      '.test' => 'test',
      'rspec/test' => 'rspectest',
      '/./test' => 'test',
      '///.///' => '',
      '...' => '',
      '' => ''
    }.each do |input, output|
      context "using #{input}" do
        it { expect(subject.sanitize_labels(input)).to eq(output) }
      end
    end
  end
end
