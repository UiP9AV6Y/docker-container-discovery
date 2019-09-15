# frozen_string_literal: true

RSpec.describe Docker::ContainerDiscovery::Logger do
  describe '#call' do
    before do
      allow(Time).to receive(:now).and_return(Time.at(1_234_567_890))
    end

    context 'without arguments' do
      let(:lines) do
        [
          '[2009-02-13T23:31:30] ',
          nil
        ]
      end
      it do
        expect { subject.call {} }.to output(lines.join("\n")).to_stdout
      end
    end

    context 'with legacy usage' do
      let(:lines) do
        [
          '[2009-02-13T23:31:30] legacy',
          nil
        ]
      end
      it do
        expect { subject.call('legacy') {} }.to output(lines.join("\n")).to_stdout
      end
    end

    context 'with subject and block' do
      let(:lines) do
        [
          '[2009-02-13T23:31:30] test',
          nil
        ]
      end
      it do
        expect { subject.call(RSpec) { 'test' } }.to output(lines.join("\n")).to_stdout
      end
    end

    context 'with argument' do
      let(:lines) do
        [
          '[2009-02-13T23:31:30] test',
          '                      rspec',
          nil
        ]
      end
      it do
        expect { subject.call(RSpec, 'rspec') { 'test' } }.to output(lines.join("\n")).to_stdout
      end
    end

    context 'with arguments' do
      let(:lines) do
        [
          '[2009-02-13T23:31:30] test',
          '                      one',
          '                      two',
          nil
        ]
      end
      it do
        expect { subject.call(RSpec, 'one', 'two') { 'test' } }.to output(lines.join("\n")).to_stdout
      end
    end
  end
end
