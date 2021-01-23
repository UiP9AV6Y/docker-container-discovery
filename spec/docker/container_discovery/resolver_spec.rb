# frozen_string_literal: true

RSpec.describe Docker::ContainerDiscovery::Resolver do
  subject do
    formatter = Docker::ContainerDiscovery::LabelFormatter.new('{image.name}.spec')
    logger = double
    allow(logger).to receive(:call)
    allow(logger).to receive(:format_argument)

    described_class.new(formatter, logger,
                        container_cidr: '127.1.2.3/32',
                        advertise_address: '127.2.4.6',
                        advertise_name: 'public',
                        contact: 'contact.name',
                        tld: 'spec.test.',
                        refresh: 123,
                        retry: 456,
                        expire: 789,
                        min_ttl: 101,
                        res_ttl: 112)
  end

  describe '#serial' do
    before do
      allow(Time).to receive(:now).and_return(Time.at(1_234_567_890))
    end

    it do
      expect(subject.serial).to eq(0)
    end
  end

  describe '#name' do
    context 'without arguments' do
      it do
        expect(subject.name).to eq(Resolv::DNS::Name.create('spec.test.'))
      end
    end

    context 'with name' do
      it do
        expect(subject.name('test-case')).to eq(Resolv::DNS::Name.create('test-case.spec.test.'))
      end
    end
  end

  describe '#rev_name' do
    context 'with address' do
      it do
        expect(subject.rev_name('12.34.56.78')).to eq(Resolv::DNS::Name.create('78.56.34.12.in-addr.arpa.'))
      end
    end
  end

  describe '#zone_master' do
    it do
      expect(subject.zone_master).to eq(Resolv::DNS::Name.create('public.spec.test.'))
    end
  end

  describe '#zone_contact' do
    it do
      expect(subject.zone_contact).to eq(Resolv::DNS::Name.create('contact\\.name.spec.test.'))
    end
  end

  describe '#zone_ptr' do
    it do
      expect(subject.zone_ptr).to eq(Resolv::DNS::Name.create('6.4.2.127.in-addr.arpa.'))
    end
  end

  describe '#advertise_addr' do
    it do
      expect(subject.advertise_addr).to eq('127.2.4.6')
    end
  end

  describe '#reverse' do
    {
      '12.34.56.78' => '78.56.34.12'
    }.each do |input, output|
      context "using '#{input}'" do
        it do
          expect(subject.reverse(input)).to eq(output)
        end
      end
    end
  end
end
